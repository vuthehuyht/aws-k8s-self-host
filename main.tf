resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr
  tags       = merge(var.tags, { Name = "${var.tags.Project}-vpc" })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  map_public_ip_on_launch = true
  tags                    = merge(var.tags, { Name = "${var.tags.Project}-public-subnet" })
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_subnet_cidr
  map_public_ip_on_launch = false
  tags                    = merge(var.tags, { Name = "${var.tags.Project}-private-subnet" })
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.tags.Project}-igw" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = merge(var.tags, { Name = "${var.tags.Project}-public-rt" })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "ssh_http" {
  name   = "${var.tags.Project}-sg"
  vpc_id = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.tags.Project}-sg" })
}

# Allow SSH only from bastion security group into worker SG
resource "aws_security_group_rule" "allow_ssh_from_bastion" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ssh_http.id
  source_security_group_id = aws_security_group.bastion_sg.id
  description              = "Allow SSH from bastion only"
}

resource "aws_instance" "node" {
  count                  = var.instance_count
  ami                    = var.ami
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.ssh_http.id]

  # Ensure DNS instance exists first and configure resolv to use internal DNS
  depends_on = [aws_instance.dns]

  user_data = <<-EOF
                #!/bin/bash
                set -e
                # write resolver to use internal DNS server and Cloudflare as fallback
                cat > /etc/resolv.conf <<RES
                nameserver ${aws_instance.dns.private_ip}
                nameserver 1.1.1.1
                options rotate
                RES
                EOF

  root_block_device {
    volume_size           = 100
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # worker nodes intentionally have no key pair to prevent direct SSH
  key_name = null

  tags = merge(var.tags, { Name = "${var.tags.Project}-node-${count.index + 1}" })
}

resource "aws_vpc_dhcp_options" "custom_dns" {
  domain_name_servers = [aws_instance.dns.private_ip, "1.1.1.1"]
  tags                = merge(var.tags, { Name = "${var.tags.Project}-dhcp-options" })
}

resource "aws_vpc_dhcp_options_association" "this" {
  vpc_id          = aws_vpc.this.id
  dhcp_options_id = aws_vpc_dhcp_options.custom_dns.id
}

resource "aws_eip" "nat_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.gw]
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public.id
  tags          = merge(var.tags, { Name = "${var.tags.Project}-nat" })
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = merge(var.tags, { Name = "${var.tags.Project}-private-rt" })
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# Bastion host in public subnet
resource "aws_instance" "bastion" {
  ami                    = var.ami
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  key_name = aws_key_pair.bastion_key.key_name

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = merge(var.tags, { Name = "${var.tags.Project}-bastion" })
}

resource "aws_security_group" "bastion_sg" {
  name   = "${var.tags.Project}-bastion-sg"
  vpc_id = aws_vpc.this.id

  ingress {
    description = "SSH only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.tags.Project}-bastion-sg" })
}

# Elastic IP for bastion
resource "aws_eip" "bastion_eip" {
  instance = aws_instance.bastion.id
  domain   = "vpc"
}

# Security group for DNS server
resource "aws_security_group" "dns_sg" {
  name   = "${var.tags.Project}-dns-sg"
  vpc_id = aws_vpc.this.id

  # allow DNS queries from worker nodes (they use aws_security_group.ssh_http)
  ingress {
    description              = "Allow DNS TCP"
    from_port                = 53
    to_port                  = 53
    protocol                 = "tcp"
    security_groups          = [aws_security_group.ssh_http.id]
  }

  ingress {
    description              = "Allow DNS UDP"
    from_port                = 53
    to_port                  = 53
    protocol                 = "udp"
    security_groups          = [aws_security_group.ssh_http.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.tags.Project}-dns-sg" })
}

# DNS server instance in private subnet (dnsmasq)
resource "aws_instance" "dns" {
  ami                    = var.ami
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.dns_sg.id]

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # private-only, no key pair
  key_name = null

  user_data = <<-EOF
    #!/bin/bash
    set -e
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y dnsmasq
    # configure dnsmasq to listen on all interfaces and forward to public DNS
    sed -i 's/^#listen-address=/listen-address=0.0.0.0/' /etc/dnsmasq.conf || true
    echo "server=1.1.1.1" >> /etc/dnsmasq.conf
    echo "no-resolv" >> /etc/dnsmasq.conf
    systemctl enable dnsmasq
    systemctl restart dnsmasq
    EOF

  tags = merge(var.tags, { Name = "${var.tags.Project}-dns" })
}

# Generate SSH key for bastion
resource "tls_private_key" "bastion" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "bastion_key" {
  key_name   = "${var.tags.Project}-bastion-key"
  public_key = tls_private_key.bastion.public_key_openssh
}

resource "local_file" "bastion_private_key" {
  content         = tls_private_key.bastion.private_key_pem
  filename        = "${path.module}/bastion_key.pem"
  file_permission = "0600"
}

# If var.ami is empty, look up a recent Ubuntu 24 LTS AMI for the region (Canonical)


# Optional: run Ansible locally to configure the cluster
resource "null_resource" "run_ansible" {
  count = var.run_ansible ? 1 : 0

  triggers = {
    bastion_ip = aws_eip.bastion_eip.public_ip
    nodes      = join(",", aws_instance.node.*.private_ip)
  }

  provisioner "local-exec" {
    command = "bash ./scripts/run_ansible.sh ansible/site.yml"
    environment = {
      TF_SSH_KEY  = var.ssh_private_key_path
      TF_SSH_USER = var.bastion_ssh_user
    }
  }
}

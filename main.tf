resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr
  tags       = merge(var.tags, { Name = "${var.tags.Project}-vpc" })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  map_public_ip_on_launch = true
  tags                   = merge(var.tags, { Name = "${var.tags.Project}-public-subnet" })
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_subnet_cidr
  map_public_ip_on_launch = false
  tags = merge(var.tags, { Name = "${var.tags.Project}-private-subnet" })
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
  count         = var.instance_count
  ami           = var.ami
  instance_type = var.instance_type
  subnet_id     = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.ssh_http.id]

  root_block_device {
    volume_size = 100
    volume_type = "gp3"
    delete_on_termination = true
  }

  key_name = length(trimspace(var.key_name)) > 0 ? var.key_name : null

  tags = merge(var.tags, { Name = "${var.tags.Project}-node-${count.index + 1}" })
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"
  depends_on = [aws_internet_gateway.gw]
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public.id
  tags = merge(var.tags, { Name = "${var.tags.Project}-nat" })
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
  ami           = var.ami
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    delete_on_termination = true
  }

  key_name = length(trimspace(var.key_name)) > 0 ? var.key_name : null

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
      TF_SSH_KEY = var.ssh_private_key_path
      TF_SSH_USER = var.bastion_ssh_user
    }
  }
}

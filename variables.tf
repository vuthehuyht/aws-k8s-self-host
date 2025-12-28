variable "aws_region" {
  description = "AWS region to create resources in"
  type        = string
  default     = "us-east-1"
}

variable "instance_count" {
  description = "Number of EC2 instances to create"
  type        = number
  default     = 7
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3a.medium"
}

variable "ami" {
  description = "AMI ID to use for instances (Linux)"
  type        = string
  default     = "ami-0c94855ba95c71c99" # Amazon Linux 2 in us-east-1 (example). Override in tfvars.
}

variable "key_name" {
  description = "Existing EC2 key pair name for SSH access (optional)"
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Public subnet CIDR block"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "Private subnet CIDR block"
  type        = string
  default     = "10.0.2.0/24"
}

variable "tags" {
  description = "Map of tags to apply to resources"
  type        = map(string)
  default     = { Project = "aws-k8s-self-host" }
}

variable "run_ansible" {
  description = "If true, run Ansible playbook after resources are created (requires local ansible)"
  type        = bool
  default     = false
}

variable "ssh_private_key_path" {
  description = "Path to the SSH private key file corresponding to the EC2 key pair (used by Ansible locally)"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "bastion_ssh_user" {
  description = "SSH user for the bastion host (used for proxy/jump)"
  type        = string
  default     = "ec2-user"
}

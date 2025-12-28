output "instance_ips" {
  description = "Public IPs of the created instances"
  value       = [for i in aws_instance.node : i.public_ip]
}

output "instance_ids" {
  description = "IDs of the created instances"
  value       = [for i in aws_instance.node : i.id]
}

output "instance_private_ips" {
  description = "Private IPs of the created private instances"
  value       = [for i in aws_instance.node : i.private_ip]
}

output "bastion_public_ip" {
  description = "Public IP of the bastion host"
  value       = aws_eip.bastion_eip.public_ip
}


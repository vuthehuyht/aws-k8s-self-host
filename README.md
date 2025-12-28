# AWS EC2 Terraform: 7 Linux servers

This Terraform project provisions 7 Linux EC2 instances on AWS with the following specs:

- 2 vCPU (example instance type `t3a.small`)
- 4 GB RAM (approx for `t3a.small`)
- 100 GB root EBS volume

Files:

- `versions.tf` - Terraform version and provider requirements
- `provider.tf` - AWS provider configuration
- `variables.tf` - Input variables and defaults
- `main.tf` - VPC, subnet, SG, and EC2 instances
- `outputs.tf` - Instance IDs and public IPs
- `terraform.tfvars.example` - Example values for overrides

Quick start:

1. Install Terraform 1.0+
2. Update `terraform.tfvars` from `terraform.tfvars.example` and set `ami` and `key_name` if needed.
3. Export AWS credentials or configure AWS CLI

```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=us-east-1

terraform init
terraform plan -out plan.out
terraform apply "plan.out"
```

Notes:

- The `instance_type` default is `t3a.medium` (2 vCPU, 4 GiB RAM). Adjust `instance_type` in variables if you prefer a different flavor.
- The `ami` value is region-specific — replace with a current Linux AMI for your chosen region.
- This project creates a new VPC and public subnet. If you prefer existing networking, modify `main.tf` accordingly.

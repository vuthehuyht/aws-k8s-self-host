#!/usr/bin/env bash
set -euo pipefail

# This script expects to be run from repository root.
# It reads outputs from terraform to build an inventory and runs ansible-playbook using bastion as jump host.

TF_DIR="$(pwd)"
if [ ! -f "$TF_DIR/terraform.tfstate" ]; then
  echo "terraform.tfstate not found in $TF_DIR — ensure you've run 'terraform apply'"
  exit 1
fi

BASTION_IP=$(terraform output -raw bastion_public_ip)
PRIVATE_IPS=$(terraform output -json instance_private_ips | jq -r '.[]')

INVENTORY_FILE="$TF_DIR/ansible/inventory.ini"
mkdir -p "$TF_DIR/ansible"
cat > "$INVENTORY_FILE" <<EOF
[bastion]
$BASTION_IP ansible_user=${TF_SSH_USER:-ec2-user} ansible_private_key_file=${TF_SSH_KEY:-$HOME/.ssh/id_rsa}

[workers]
EOF
for ip in $PRIVATE_IPS; do
  echo "$ip ansible_user=${TF_SSH_USER:-ec2-user} ansible_ssh_common_args='-o ProxyCommand=ssh -W %h:%p -q ${TF_SSH_USER:-ec2-user}@${BASTION_IP} -i ${TF_SSH_KEY:-$HOME/.ssh/id_rsa}'" >> "$INVENTORY_FILE"
done

echo "Inventory written to $INVENTORY_FILE"

ANSIBLE_PLAYBOOK=${1:-ansible/site.yml}
ansible-playbook -i "$INVENTORY_FILE" "$ANSIBLE_PLAYBOOK"

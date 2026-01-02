Ansible project for aws-k8s-self-host

Inventory layout:

- `ansible/hosts.ini` : simple flat inventory (for quick testing)
- `ansible/inventory/production/hosts.ini` : production inventory with `group_vars/` and `host_vars/`
 - `ansible/inventory/sandbox/hosts.ini` : sandbox inventory for testing

Usage examples:

- Quick run using simple inventory:

```bash
ansible-playbook -i ansible/hosts.ini ansible/dns.yml --limit dns
```

- Production inventory (recommended):
 - Production inventory (recommended):

```bash
ansible-playbook -i ansible/inventory/production/hosts.ini ansible/dns.yml --limit dns
```

- Sandbox inventory (for testing):

```bash
ansible-playbook -i ansible/inventory/sandbox/hosts.ini ansible/dns.yml --limit dns
```

Group and host variables:

- `ansible/inventory/production/group_vars/dns.yml` contains DNS-specific defaults (forwarders, listen address).
- `ansible/inventory/production/host_vars/10.0.1.10.yml` contains host-specific vars for the DNS server.

If you provision infrastructure with Terraform, consider scripting inventory generation using `terraform output -json` and writing the resulting hosts into `ansible/inventory/production/hosts.ini`.

# Runbooks

---

## Deploy a VM on local Proxmox (onprem)

### Prerequisites

- Proxmox VE installed and accessible via web UI
- Terraform installed (`npm run setup`)
- Ansible installed (`pip install ansible`)
- SSH key pair on your machine (`~/.ssh/id_ed25519`)

---

### Step 1 — Create a Proxmox API token

In the Proxmox web UI:

1. **Datacenter → Permissions → API Tokens → Add**
   - User: `root@pam`
   - Token ID: `terraform`
   - Uncheck **Privilege Separation**
   - Copy the token secret — it is shown **only once**

2. **Datacenter → Permissions → Add → API Token Permission**
   - Path: `/`
   - API Token: `root@pam!terraform`
   - Role: `Administrator`
   - Check **Propagate**

---

### Step 2 — Authorize your SSH key on Proxmox

The bpg/proxmox Terraform provider uses SSH to import VM disks. Your public key must be authorized on the Proxmox root account.

```bash
ssh-copy-id -i ~/.ssh/id_ed25519 root@<PROXMOX_IP>
```

Verify it works:

```bash
ssh root@<PROXMOX_IP> "echo ok"
```

---

### Step 3 — Configure Terraform variables

```bash
cp terraform/envs/onprem/terraform.tfvars.example terraform/envs/onprem/terraform.tfvars
```

Edit `terraform.tfvars` with your values:

| Variable              | Description                              | Example                  |
|-----------------------|------------------------------------------|--------------------------|
| `proxmox_endpoint`    | Proxmox API URL                          | `https://172.16.x.x:8006`|
| `proxmox_node`        | Proxmox node name                        | `pve`                    |
| `proxmox_node_address`| Proxmox IP for SSH                       | `172.16.x.x`             |
| `vm_ip_cidr`          | VM static IP in CIDR notation            | `172.16.x.x/24`          |
| `vm_gateway`          | LAN default gateway                      | `172.16.x.x`             |
| `vm_ssh_public_key`   | Your SSH public key (`cat ~/.ssh/id_ed25519.pub`) | `ssh-ed25519 AAAA...` |

Set the API token as an environment variable (use single quotes to avoid bash interpreting `!`):

```bash
export TF_VAR_proxmox_api_token='root@pam!terraform=<TOKEN_SECRET>'
```

---

### Step 4 — Deploy with Terraform

```bash
npm run tf:init:onprem
npm run tf:plan:onprem
terraform -chdir=terraform/envs/onprem apply
```

Terraform will:
1. Download the Ubuntu 22.04 cloud image to Proxmox local storage (~660 MB, once)
2. Create the VM with cloud-init (static IP, SSH key, user `ubuntu`)

---

### Step 5 — Configure the VM with Ansible

Once the VM is up and reachable:

```bash
cd ansible
ansible-playbook playbooks/services-vm.yml
```

This installs base packages, Docker CE, and UFW firewall rules.

---

### Network requirements

- The VM IP must be in the same L2 segment as Proxmox (same bridge `vmbr0`)
- `vm_ip_cidr` and `vm_gateway` must be consistent with your LAN subnet
- Verify the VM is reachable: `ping <VM_IP>`

---

### Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `the API token must be in the format USER@REALM!TOKENID=UUID` | Bash interpreted `!` in double quotes | Use single quotes: `export TF_VAR_proxmox_api_token='...'` |
| `HTTP 403 - Permission check failed` | Token missing permission on `/` | Add Administrator permission on path `/` in Proxmox UI |
| `unable to authenticate user root over SSH` | SSH key not on Proxmox | Run `ssh-copy-id -i ~/.ssh/id_ed25519 root@<PROXMOX_IP>` |
| `value does not look like a valid ipv4 network configuration` | Missing subnet mask | Use CIDR notation: `192.168.x.x/24` |
| VM unreachable after creation | VM IP not in LAN subnet | Ensure `vm_ip_cidr` is in the same subnet as your LAN and `vmbr0` |

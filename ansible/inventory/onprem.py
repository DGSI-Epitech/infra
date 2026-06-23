#!/usr/bin/env python3
"""
Inventaire Ansible dynamique — lit config.env à la racine du repo.
Les IPs des VMs sont récupérées (par ordre de priorité) :
  1. Variables d'environnement VAULT_IP / SERVICES_IP  (CI)
  2. Outputs Terraform  (exécution locale, VMs déjà provisionnées)
  3. config.env  (fallback statique)
Usage : ansible-playbook ... -i inventory/onprem.py
"""
import json
import os
import subprocess
import sys

def load_env(path):
    env = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            key, _, val = line.partition("=")
            env[key.strip()] = val.strip().strip('"').strip("'")
    return env

def terraform_output(tf_dir):
    try:
        result = subprocess.run(
            ["terraform", "output", "-json"],
            cwd=tf_dir,
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode != 0:
            return {}
        outputs = json.loads(result.stdout)
        ips = {}
        for key, out in outputs.items():
            # ipv4_addresses est une liste de listes : [[loopback], [vraie ip]]
            if isinstance(out.get("value"), list):
                for iface in out["value"]:
                    if isinstance(iface, list):
                        for ip in iface:
                            if ip != "127.0.0.1":
                                ips[key] = ip
                                break
        return ips
    except Exception:
        return {}

repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
env       = load_env(os.path.join(repo_root, "config.env"))
tf_dir    = os.path.join(repo_root, "terraform", "envs", "onprem")

ssh_key           = env.get("SSH_PRIVATE_KEY_FILE", "~/.ssh/id_ed25519")
vm_user_op        = env.get("VM_USERNAME_OP", "dgsi-op")
vm_user_cloud     = env.get("VM_USERNAME_CLOUD", "dgsi-cloud")
ops_ip            = os.environ.get("OPS_IP") or env.get("VM_IP_OPS", "").split("/")[0]
services_ip       = os.environ.get("SERVICES_IP") or env.get("VM_IP_SERVICES", "").split("/")[0]
bastion_ip        = env.get("VM_IP_BASTION", "").split("/")[0]
web_ip            = env.get("VM_IP_WEB", "").split("/")[0]
pfsense_op_wan    = env.get("PFSENSE_OP_WAN", "")
pfsense_cloud_wan = env.get("PFSENSE_CLOUD_WAN", "")
pfsense_password  = env.get("PFSENSE_PASSWORD", "pfsense")
vm_password       = env.get("VM_PASSWORD", "")
pfsense_username  = env.get("PFSENSE_USERNAME", "admin")
proxmox_host        = env.get("PROXMOX_HOST", "")
proxmox_host_remote = env.get("PROXMOX_HOST_REMOTE") or env.get("PROXMOX_NODE_ADDRESS_REMOTE", "")

# Env proxmox ecole (pfSense comme jump host) — garder pour l'autre environnement
# proxy_jump       = f"-o StrictHostKeyChecking=no -o ProxyJump={pfsense_username}@{pfsense_op_wan} -o ServerAliveInterval=30 -o ServerAliveCountMax=10"
# proxy_jump_cloud = f"-o StrictHostKeyChecking=no -o ProxyJump={pfsense_username}@{pfsense_cloud_wan} -o ServerAliveInterval=30 -o ServerAliveCountMax=10"

# Env proxmox mel (Proxmox comme jump host — root@PROXMOX_HOST)
# Ancien: proxy_jump utilisait pfsense_op_wan comme jump → cassait quand PFSENSE_OP_WAN = IP interne
proxmox_ssh_user  = env.get("PROXMOX_SSH_USER", "root")
proxy_jump        = f"-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyJump={proxmox_ssh_user}@{proxmox_host} -o ServerAliveInterval=30 -o ServerAliveCountMax=10"
# Bastion/web sont sur PVE2 (cloud) — hôte Proxmox différent de l'onprem (PROXMOX_HOST)
proxy_jump_cloud  = f"-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyJump={proxmox_ssh_user}@{proxmox_host_remote} -o ServerAliveInterval=30 -o ServerAliveCountMax=10"

# ProxyJump pour pfSense (Proxmox → IP WAN interne pfSense)
proxy_jump_pfsense_op    = f"-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyJump={proxmox_ssh_user}@{proxmox_host}"
proxy_jump_pfsense_cloud = f"-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyJump={proxmox_ssh_user}@{proxmox_host_remote}"

pfsense_common = {
    "ansible_user":               "root",
    "ansible_password":           pfsense_password,
    "ansible_connection":         "ssh",
    "ansible_python_interpreter": "/usr/local/bin/python3.11",
}

tf_ips = {}
vault_ip    = os.environ.get("VAULT_IP")
services_ip = os.environ.get("SERVICES_IP")

# Si une des deux IPs manque, on interroge Terraform
if not vault_ip or not services_ip:
    tf_ips = terraform_output(tf_dir)

vault_ip    = vault_ip    or tf_ips.get("vault_vm_ip")
services_ip = services_ip or tf_ips.get("services_vm_ip")

inventory = {
    "ops": {
        "hosts": ["ops-vm"]
    },
    "services": {
        "hosts": ["services-vm"]
    },
    "bastion": {
        "hosts": ["bastion-vm"]
    },
    "web": {
        "hosts": ["web-vm"]
    },
    "Pfsense_OP": {
        "hosts": ["pfsense-op"]
    },
    "Pfsense_Cloud": {
        "hosts": ["pfsense-cloud"]
    },
    "_meta": {
        "hostvars": {
            "ops-vm": {
                "ansible_host":                ops_ip,
                "ansible_user":                vm_user_op,
                "ansible_become_pass":         vm_password,
                "ansible_ssh_private_key_file": ssh_key,
                "ansible_ssh_common_args":      proxy_jump,
            },
            "services-vm": {
                "ansible_host":                services_ip,
                "ansible_user":                vm_user_op,
                "ansible_become_pass":         vm_password,
                "ansible_ssh_private_key_file": ssh_key,
                "ansible_ssh_common_args":      proxy_jump,
            },
            "bastion-vm": {
                "ansible_host":                bastion_ip,
                "ansible_user":                vm_user_cloud,
                "ansible_become_pass":         vm_password,
                "ansible_ssh_private_key_file": ssh_key,
                "ansible_ssh_common_args":      proxy_jump_cloud,
            },
            "web-vm": {
                "ansible_host":                web_ip,
                "ansible_user":                vm_user_cloud,
                "ansible_become_pass":         vm_password,
                "ansible_ssh_private_key_file": ssh_key,
                "ansible_ssh_common_args":      proxy_jump_cloud,
            },
            "pfsense-op": {
                **pfsense_common,
                "ansible_host":            pfsense_op_wan,
                "ansible_ssh_common_args": proxy_jump_pfsense_op,
            },
            "pfsense-cloud": {
                **pfsense_common,
                "ansible_host": pfsense_cloud_wan,
                "ansible_port": 2222,
            },
        }
    }
}

if "--list" in sys.argv or len(sys.argv) == 1:
    print(json.dumps(inventory, indent=2))
elif "--host" in sys.argv:
    host = sys.argv[sys.argv.index("--host") + 1]
    print(json.dumps(inventory["_meta"]["hostvars"].get(host, {})))

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

proxmox_host = env.get("PROXMOX_HOST", "")
ssh_key      = env.get("SSH_PRIVATE_KEY_FILE", "~/.ssh/id_ed25519")
proxy_jump   = f"-o StrictHostKeyChecking=no -o ProxyJump=root@{proxmox_host}"

tf_ips = {}
vault_ip    = os.environ.get("VAULT_IP")
services_ip = os.environ.get("SERVICES_IP")

# Si une des deux IPs manque, on interroge Terraform
if not vault_ip or not services_ip:
    tf_ips = terraform_output(tf_dir)

vault_ip    = vault_ip    or tf_ips.get("vault_vm_ip")
services_ip = services_ip or tf_ips.get("services_vm_ip")

inventory = {
    "vault": {
        "hosts": ["vault-vm"]
    },
    "services": {
        "hosts": ["services-vm"]
    },
    "pfsense": {
        "hosts": ["pfsense-fw-01"]
    },
    "_meta": {
        "hostvars": {
            "vault-vm": {
                "ansible_host":                vault_ip,
                "ansible_user":                "ubuntu",
                "ansible_ssh_private_key_file": ssh_key,
                "ansible_ssh_common_args":      proxy_jump,
            },
            "services-vm": {
                "ansible_host":                services_ip,
                "ansible_user":                "ubuntu",
                "ansible_ssh_private_key_file": ssh_key,
                "ansible_ssh_common_args":      proxy_jump,
            },
            "pfsense-fw-01": {
                "ansible_host":                env.get("VM_GATEWAY", ""),
                "ansible_user":                "admin",
                "ansible_ssh_private_key_file": ssh_key,
                "ansible_connection":           "ssh",
                "ansible_python_interpreter":   "/usr/local/bin/python3.11",
            },
        }
    }
}

if "--list" in sys.argv or len(sys.argv) == 1:
    print(json.dumps(inventory, indent=2))
elif "--host" in sys.argv:
    host = sys.argv[sys.argv.index("--host") + 1]
    print(json.dumps(inventory["_meta"]["hostvars"].get(host, {})))

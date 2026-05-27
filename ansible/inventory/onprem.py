#!/usr/bin/env python3
"""
Inventaire Ansible dynamique — lit config.env à la racine du repo.
Usage : ansible-playbook ... -i inventory/onprem.py
"""
import json
import os
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

repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
env = load_env(os.path.join(repo_root, "config.env"))

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
proxy_jump        = f"-o StrictHostKeyChecking=no -o ProxyJump=admin@{pfsense_op_wan} -o ServerAliveInterval=30 -o ServerAliveCountMax=10"
proxy_jump_cloud  = f"-o StrictHostKeyChecking=no -o ProxyJump=admin@{pfsense_cloud_wan} -o ServerAliveInterval=30 -o ServerAliveCountMax=10"

pfsense_common = {
    "ansible_user":               "admin",
    "ansible_password":           pfsense_password,
    "ansible_connection":         "ssh",
    "ansible_python_interpreter": "/usr/local/bin/python3.11",
}

# Format JSON attendu par Ansible pour un script d'inventaire dynamique
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
                "ansible_host": pfsense_op_wan,
            },
            "pfsense-cloud": {
                **pfsense_common,
                "ansible_host": pfsense_cloud_wan,
            },
        }
    }
}

if "--list" in sys.argv or len(sys.argv) == 1:
    print(json.dumps(inventory, indent=2))
elif "--host" in sys.argv:
    host = sys.argv[sys.argv.index("--host") + 1]
    print(json.dumps(inventory["_meta"]["hostvars"].get(host, {})))

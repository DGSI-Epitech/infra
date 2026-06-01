#!/usr/bin/env bash
# Déploiement Ansible uniquement (après que les VMs sont up via deploy_terra.sh)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANSIBLE_DIR="$REPO_ROOT/ansible"
CONFIG_FILE="$REPO_ROOT/config.env"

# --- Vérifications ---

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Erreur : $CONFIG_FILE manquant."
  exit 1
fi

source "$CONFIG_FILE"

SSH_KEY_FILE="${SSH_PRIVATE_KEY_FILE/#\~/$HOME}"

if [[ ! -f "$SSH_KEY_FILE" ]]; then
  echo "Erreur : clé SSH ${SSH_KEY_FILE} introuvable."
  exit 1
fi

# --- Playbooks ---

cd "$ANSIBLE_DIR"

echo ""
echo "==> [1/4] Ansible services-vm (Netbox)..."
ansible-playbook playbooks/services-vm.yml -i inventory/onprem.py

ansible-playbook playbooks/tls.yml         -i inventory/onprem.py

echo ""
echo "==> [2/4] Ansible Vault..."
ansible-playbook playbooks/vault.yml -i inventory/onprem.py

echo ""
echo "==> [3/4] Ansible ELK..."
ansible-playbook playbooks/elk.yml -i inventory/onprem.py

echo ""
echo "==> [4/4] Ansible Elastic Agent..."
ansible-playbook playbooks/elastic-agent.yml -i inventory/onprem.py

echo ""
echo "==> Déploiement Ansible terminé."

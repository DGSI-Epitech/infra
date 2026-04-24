#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ONPREM_DIR="$REPO_ROOT/terraform/envs/onprem"

PROXMOX_HOST="192.168.139.128"
PROXMOX_API="https://${PROXMOX_HOST}:8006/api2/json"
PROXMOX_USER="${TF_VAR_proxmox_username:-root@pam}"

# --- Vérifications ---

if [[ -z "${TF_VAR_proxmox_password:-}" ]]; then
  echo "Erreur : TF_VAR_proxmox_password n'est pas défini."
  echo "  export TF_VAR_proxmox_password='ton-mot-de-passe-root'"
  exit 1
fi

if [[ ! -f "$ONPREM_DIR/terraform.tfvars" ]]; then
  echo "Erreur : $ONPREM_DIR/terraform.tfvars manquant."
  echo "  cp terraform/envs/onprem/terraform.tfvars.example terraform/envs/onprem/terraform.tfvars"
  exit 1
fi

# --- Auth Proxmox (ticket session) ---

echo ""
echo "==> Authentification Proxmox..."
AUTH=$(curl -s -k -X POST "${PROXMOX_API}/access/ticket" \
  --data-urlencode "username=${PROXMOX_USER}" \
  --data-urlencode "password=${TF_VAR_proxmox_password}")
TICKET=$(echo "$AUTH" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['ticket'])")
CSRF=$(echo "$AUTH"   | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['CSRFPreventionToken'])")

# --- Nettoyage des VMs orphelines ---

echo "==> Nettoyage des VMs orphelines (200, 201)..."
for VMID in 200 201; do
  STATUS=$(curl -s -k -b "PVEAuthCookie=${TICKET}" \
    "${PROXMOX_API}/nodes/pve/qemu/${VMID}/status/current" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('status','notfound'))" 2>/dev/null || echo "notfound")

  if [[ "$STATUS" != "notfound" ]]; then
    echo "    VM ${VMID} trouvée (status: ${STATUS}), suppression..."
    # Stop si running
    if [[ "$STATUS" == "running" ]]; then
      curl -s -k -X POST "${PROXMOX_API}/nodes/pve/qemu/${VMID}/status/stop" \
        -H "CSRFPreventionToken: ${CSRF}" -b "PVEAuthCookie=${TICKET}" > /dev/null
      sleep 5
    fi
    # Destroy
    curl -s -k -X DELETE "${PROXMOX_API}/nodes/pve/qemu/${VMID}?destroy-unreferenced-disks=1&purge=1" \
      -H "CSRFPreventionToken: ${CSRF}" -b "PVEAuthCookie=${TICKET}" > /dev/null
    echo "    VM ${VMID} supprimée."
  else
    echo "    VM ${VMID} absente, rien à faire."
  fi
done

# --- Déploiement Terraform ---

echo ""
echo "==> Déploiement onprem (VMs + pfSense)..."
cd "$ONPREM_DIR"
terraform init -input=false -upgrade
terraform apply -input=false -auto-approve

echo ""
echo "==> Déploiement terminé."
echo "    Lancer Ansible quand les VMs sont prêtes :"
echo "    cd ansible && ansible-playbook playbooks/vault.yml -i inventory/onprem.yml"

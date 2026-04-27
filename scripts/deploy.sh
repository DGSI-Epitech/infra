#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ONPREM_DIR="$REPO_ROOT/terraform/envs/onprem"
PACKER_DIR_PFSENSE="$REPO_ROOT/packer/pfsense-2.7"
PACKER_DIR_UBUNTU="$REPO_ROOT/packer/ubuntu-22.04"
CONFIG_FILE="$REPO_ROOT/config.env"

# --- Vérifications ---

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Erreur : $CONFIG_FILE manquant."
  echo "  cp config.env.example config.env && éditez les valeurs"
  exit 1
fi

source "$CONFIG_FILE"

PROXMOX_API="https://${PROXMOX_HOST}:8006/api2/json"
export TF_VAR_proxmox_password="${TF_VAR_proxmox_password:-${PROXMOX_PASSWORD}}"

if [[ -z "${TF_VAR_proxmox_password:-}" ]]; then
  echo "Erreur : PROXMOX_PASSWORD manquant dans config.env."
  exit 1
fi

if [[ ! -f "$ONPREM_DIR/terraform.tfvars" ]]; then
  echo "Erreur : $ONPREM_DIR/terraform.tfvars manquant."
  exit 1
fi

# --- Auth Proxmox ---

echo ""
echo "==> Authentification Proxmox..."
AUTH=$(curl -s -k -X POST "${PROXMOX_API}/access/ticket" \
  --data-urlencode "username=${PROXMOX_USER}" \
  --data-urlencode "password=${TF_VAR_proxmox_password}")

echo "    Réponse API : $(echo "$AUTH" | python3 -c "import sys,json; d=json.load(sys.stdin); print('OK' if d.get('data') else d.get('errors', d))" 2>/dev/null || echo "$AUTH")"

TICKET=$(echo "$AUTH" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['ticket'])" 2>/dev/null || true)
CSRF=$(echo "$AUTH"   | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['CSRFPreventionToken'])" 2>/dev/null || true)

if [[ -z "$TICKET" ]]; then
  echo "Erreur : authentification Proxmox échouée."
  echo "  Vérifier PROXMOX_PASSWORD et l'URL ${PROXMOX_API}"
  echo "  Réponse complète : $AUTH"
  exit 1
fi
echo "    Authentifié."

# --- Nettoyage des VMs orphelines ---

echo ""
echo "==> Nettoyage des VMs (${VM_ID_UBUNTU_TEMPLATE}, ${VM_ID_PFSENSE}, ${VM_ID_SERVICES}, ${VM_ID_VAULT})..."
for VMID in "${VM_ID_UBUNTU_TEMPLATE}" "${VM_ID_PFSENSE}" "${VM_ID_SERVICES}" "${VM_ID_VAULT}"; do
  STATUS=$(curl -s -k -b "PVEAuthCookie=${TICKET}" \
    "${PROXMOX_API}/nodes/${PROXMOX_NODE}/qemu/${VMID}/status/current" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('status','notfound'))" 2>/dev/null || echo "notfound")

  if [[ "$STATUS" != "notfound" ]]; then
    echo "    VM ${VMID} trouvée (${STATUS}), suppression..."
    if [[ "$STATUS" == "running" ]]; then
      curl -s -k -X POST "${PROXMOX_API}/nodes/${PROXMOX_NODE}/qemu/${VMID}/status/stop" \
        -H "CSRFPreventionToken: ${CSRF}" -b "PVEAuthCookie=${TICKET}" > /dev/null
      sleep 5
    fi
    curl -s -k -X DELETE "${PROXMOX_API}/nodes/${PROXMOX_NODE}/qemu/${VMID}?destroy-unreferenced-disks=1&purge=1" \
      -H "CSRFPreventionToken: ${CSRF}" -b "PVEAuthCookie=${TICKET}" > /dev/null
    echo "    VM ${VMID} supprimée."
  fi
done

# --- Bridge LAN (vmbr1) ---

echo ""
echo "==> Vérification du bridge LAN (vmbr1)..."
VMBR1_STATUS=$(curl -s -k -b "PVEAuthCookie=${TICKET}" \
  "${PROXMOX_API}/nodes/${PROXMOX_NODE}/network/vmbr1" 2>/dev/null | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print('ok' if d.get('data') else 'notfound')" 2>/dev/null || echo "notfound")

if [[ "$VMBR1_STATUS" == "notfound" ]]; then
  echo "    Bridge vmbr1 absent — création..."
  curl -s -k -X POST "${PROXMOX_API}/nodes/${PROXMOX_NODE}/network" \
    -H "CSRFPreventionToken: ${CSRF}" -b "PVEAuthCookie=${TICKET}" \
    --data-urlencode "iface=vmbr1" \
    --data-urlencode "type=bridge" \
    --data-urlencode "autostart=1" \
    --data-urlencode "bridge_ports=" \
    --data-urlencode "bridge_stp=off" \
    --data-urlencode "bridge_fd=0" \
    --data-urlencode "address=172.16.255.254" \
    --data-urlencode "netmask=255.255.255.240" \
    --data-urlencode "comments=LAN pfSense S1" > /dev/null
  curl -s -k -X PUT "${PROXMOX_API}/nodes/${PROXMOX_NODE}/network" \
    -H "CSRFPreventionToken: ${CSRF}" -b "PVEAuthCookie=${TICKET}" > /dev/null
  echo "    Bridge vmbr1 créé (172.16.255.254/28)."
else
  echo "    Bridge vmbr1 déjà présent."
fi

# --- ÉTAPE 1 : Packer pfSense ---

echo ""
PFSENSE_TEMPLATE_STATUS=$(curl -s -k -b "PVEAuthCookie=${TICKET}" \
  "${PROXMOX_API}/nodes/${PROXMOX_NODE}/qemu/${VM_ID_PFSENSE_TEMPLATE}/status/current" 2>/dev/null | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('status','notfound'))" 2>/dev/null || echo "notfound")

if [[ "$PFSENSE_TEMPLATE_STATUS" == "notfound" ]]; then
  echo "==> Template pfSense (${VM_ID_PFSENSE_TEMPLATE}) absent — build Packer..."
  cd "$PACKER_DIR_PFSENSE"
  export PKR_VAR_proxmox_url="https://${PROXMOX_HOST}:8006/api2/json"
  export PKR_VAR_proxmox_username="${PROXMOX_USER}"
  export PKR_VAR_proxmox_password="${TF_VAR_proxmox_password}"
  export PKR_VAR_proxmox_node="${PROXMOX_NODE}"
  export PKR_VAR_proxmox_storage_vm="${PROXMOX_STORAGE_VM}"
  export PKR_VAR_template_vm_id="${VM_ID_PFSENSE_TEMPLATE}"
  packer init .
  packer build pfsense-2.7.pkr.hcl
  echo "    Template pfSense créé."
else
  echo "==> Template pfSense (${VM_ID_PFSENSE_TEMPLATE}) déjà présent, build Packer sauté."
fi

# --- ÉTAPE 2 : Terraform - déploiement pfSense uniquement ---
# pfSense doit tourner avant le build Ubuntu pour router le trafic de vmbr1 vers internet

echo ""
echo "==> Déploiement pfSense (phase 1)..."
cd "$ONPREM_DIR"
terraform init -input=false -upgrade
terraform apply -input=false -auto-approve \
  -target=module.pfsense \
  -var "proxmox_endpoint=https://${PROXMOX_HOST}:8006" \
  -var "proxmox_username=${PROXMOX_USER}" \
  -var "proxmox_node=${PROXMOX_NODE}" \
  -var "proxmox_node_address=${PROXMOX_HOST}" \
  -var "storage_vm=${PROXMOX_STORAGE_VM}" \
  -var "template_ubuntu_vm_id=${VM_ID_UBUNTU_TEMPLATE}" \
  -var "pfsense_template_id=${VM_ID_PFSENSE_TEMPLATE}" \
  -var "services_vm_id=${VM_ID_SERVICES}" \
  -var "vault_vm_id=${VM_ID_VAULT}" \
  -var "pfsense_vm_id=${VM_ID_PFSENSE}" \
  -var "vm_ip_cidr=${VM_IP_SERVICES}" \
  -var "vault_vm_ip_cidr=${VM_IP_VAULT}" \
  -var "vm_gateway=${VM_GATEWAY}" \
  -var "vm_ssh_public_key=${SSH_PUBLIC_KEY}" \
  -var "vm_password=${VM_PASSWORD}"

echo "    pfSense déployé — attente 30s pour qu'il soit opérationnel..."
sleep 30

# --- ÉTAPE 3 : Packer Ubuntu ---
# pfSense est maintenant actif et route le trafic de vmbr1 vers internet

echo ""
UBUNTU_TEMPLATE_STATUS=$(curl -s -k -b "PVEAuthCookie=${TICKET}" \
  "${PROXMOX_API}/nodes/${PROXMOX_NODE}/qemu/${VM_ID_UBUNTU_TEMPLATE}/status/current" 2>/dev/null | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('status','notfound'))" 2>/dev/null || echo "notfound")

if [[ "$UBUNTU_TEMPLATE_STATUS" == "notfound" ]]; then
  echo "==> Template Ubuntu (${VM_ID_UBUNTU_TEMPLATE}) absent — build Packer..."
  cd "$PACKER_DIR_UBUNTU"
  export PKR_VAR_proxmox_url="https://${PROXMOX_HOST}:8006/api2/json"
  export PKR_VAR_proxmox_username="${PROXMOX_USER}"
  export PKR_VAR_proxmox_password="${TF_VAR_proxmox_password}"
  export PKR_VAR_proxmox_node="${PROXMOX_NODE}"
  export PKR_VAR_proxmox_host="${PROXMOX_HOST}"
  export PKR_VAR_proxmox_storage_iso="local"
  export PKR_VAR_proxmox_storage_vm="${PROXMOX_STORAGE_VM}"
  export PKR_VAR_template_vm_id="${VM_ID_UBUNTU_TEMPLATE}"
  export PKR_VAR_build_username="${VM_USERNAME}"
  export PKR_VAR_build_password="${VM_PASSWORD}"
  export PKR_VAR_build_password_encrypted="${VM_PASSWORD_HASH}"
  packer init .
  packer build -on-error=abort ubuntu-22.04.pkr.hcl
  echo "    Template Ubuntu créé — attente 30s pour déverrouillage Proxmox..."
  sleep 30
else
  echo "==> Template Ubuntu (${VM_ID_UBUNTU_TEMPLATE}) déjà présent, build Packer sauté."
fi

# --- ÉTAPE 4 : Terraform - déploiement VMs services + vault ---

echo ""
echo "==> Déploiement VMs services et vault (phase 2)..."
cd "$ONPREM_DIR"
terraform apply -input=false -auto-approve \
  -var "proxmox_endpoint=https://${PROXMOX_HOST}:8006" \
  -var "proxmox_username=${PROXMOX_USER}" \
  -var "proxmox_node=${PROXMOX_NODE}" \
  -var "proxmox_node_address=${PROXMOX_HOST}" \
  -var "storage_vm=${PROXMOX_STORAGE_VM}" \
  -var "template_ubuntu_vm_id=${VM_ID_UBUNTU_TEMPLATE}" \
  -var "pfsense_template_id=${VM_ID_PFSENSE_TEMPLATE}" \
  -var "services_vm_id=${VM_ID_SERVICES}" \
  -var "vault_vm_id=${VM_ID_VAULT}" \
  -var "pfsense_vm_id=${VM_ID_PFSENSE}" \
  -var "vm_ip_cidr=${VM_IP_SERVICES}" \
  -var "vault_vm_ip_cidr=${VM_IP_VAULT}" \
  -var "vm_gateway=${VM_GATEWAY}" \
  -var "vm_ssh_public_key=${SSH_PUBLIC_KEY}" \
  -var "vm_password=${VM_PASSWORD}"

echo ""
echo "==> Déploiement terminé."
echo "    Lancer Ansible quand les VMs sont prêtes :"
echo "    cd ansible && ansible-playbook playbooks/vault.yml -i inventory/onprem.yml"

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

if [[ -z "${SSH_PRIVATE_KEY_FILE:-}" ]]; then
  echo "Erreur : SSH_PRIVATE_KEY_FILE manquant dans config.env."
  echo "  Ajouter : SSH_PRIVATE_KEY_FILE=\"~/.ssh/id_ed25519\""
  exit 1
fi

if [[ -z "${SSH_PUBLIC_KEY:-}" ]]; then
  echo "Erreur : SSH_PUBLIC_KEY manquant dans config.env."
  echo "  Ajouter : SSH_PUBLIC_KEY=\"\$(cat ~/.ssh/id_ed25519.pub)\""
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
echo "==> Nettoyage des VMs (${VM_ID_PFSENSE}, ${VM_ID_SERVICES}, ${VM_ID_VAULT})..."
for VMID in "${VM_ID_PFSENSE}" "${VM_ID_SERVICES}" "${VM_ID_VAULT}"; do
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
  export PKR_VAR_pfsense_admin_ssh_public_key="${SSH_PUBLIC_KEY}"
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
  -var "vm_ssh_public_key=${SSH_PUBLIC_KEY}" \
  -var "proxmox_ssh_private_key=${SSH_PRIVATE_KEY_FILE}"

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
  export PKR_VAR_ssh_public_key="${SSH_PUBLIC_KEY}"
  export PKR_VAR_ssh_bastion_private_key_file="${SSH_PRIVATE_KEY_FILE}"
  # Password éphémère généré à la volée — utilisé uniquement pour le communicator Packer, jamais stocké
  _PACKER_PASS="$(openssl rand -base64 16 | tr -d '+/=' | head -c 20)"
  export PKR_VAR_build_password="${_PACKER_PASS}"
  export PKR_VAR_build_password_hash="$(echo "${_PACKER_PASS}" | openssl passwd -6 -stdin)"
  unset _PACKER_PASS
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
  -var "vm_ssh_public_key=${SSH_PUBLIC_KEY}" \
  -var "proxmox_ssh_private_key=${SSH_PRIVATE_KEY_FILE}"

# --- ÉTAPE 5 : Injection clé SSH + Ansible ---

# Attend que le QEMU agent soit opérationnel dans la VM
wait_for_agent() {
  local vmid="$1"
  local label="$2"
  local timeout=180
  local elapsed=0
  echo ""
  echo "==> Attente QEMU agent ${label} (VM ${vmid})..."
  while true; do
    local status
    status=$(curl -s -k -X POST \
      "${PROXMOX_API}/nodes/${PROXMOX_NODE}/qemu/${vmid}/agent/ping" \
      -H "CSRFPreventionToken: ${CSRF}" \
      -b "PVEAuthCookie=${TICKET}" 2>/dev/null | \
      python3 -c "import sys,json; d=json.load(sys.stdin); print('ok' if d.get('data') is not None else 'wait')" 2>/dev/null || echo "wait")
    [[ "$status" == "ok" ]] && break
    sleep 5
    elapsed=$((elapsed + 5))
    echo "    ${elapsed}s — QEMU agent ${label} pas encore prêt..."
    if [[ $elapsed -ge $timeout ]]; then
      echo "Erreur : QEMU agent ${label} inaccessible après ${timeout}s."
      exit 1
    fi
  done
  echo "    QEMU agent prêt sur ${label}."
}

# Injecte la clé SSH via l'API QEMU agent (contourne le bug cloud-init/autoinstall)
inject_ssh_key() {
  local vmid="$1"
  local label="$2"
  echo ""
  echo "==> Injection clé SSH dans ${label} (VM ${vmid})..."

  local tmpjson
  tmpjson=$(mktemp)
  # Le heredoc expande SSH_PUBLIC_KEY ; la clé ED25519 ne contient pas de ' ni de " ni de \
  cat > "$tmpjson" << ENDJSON
{"command":["bash","-c","mkdir -p /home/ubuntu/.ssh && echo '${SSH_PUBLIC_KEY}' > /home/ubuntu/.ssh/authorized_keys && chmod 700 /home/ubuntu/.ssh && chmod 600 /home/ubuntu/.ssh/authorized_keys && chown -R ubuntu:ubuntu /home/ubuntu/.ssh"]}
ENDJSON

  curl -s -k -X POST \
    "${PROXMOX_API}/nodes/${PROXMOX_NODE}/qemu/${vmid}/agent/exec" \
    -H "CSRFPreventionToken: ${CSRF}" \
    -b "PVEAuthCookie=${TICKET}" \
    -H "Content-Type: application/json" \
    -d "@${tmpjson}" > /dev/null

  rm -f "$tmpjson"
  sleep 5
  echo "    Clé SSH injectée dans ${label}."
}

# Récupère l'IP d'une VM via le QEMU agent (stdout = IP, stderr = progression)
get_vm_ip() {
  local vmid="$1"
  local label="$2"
  local timeout=60
  local elapsed=0
  echo "==> Récupération IP de ${label} (VM ${vmid}) via QEMU agent..." >&2
  while true; do
    local ip
    ip=$(curl -s -k -b "PVEAuthCookie=${TICKET}" \
      "${PROXMOX_API}/nodes/${PROXMOX_NODE}/qemu/${vmid}/agent/network-get-interfaces" 2>/dev/null | \
      python3 -c "
import sys, json
try:
    data = json.load(sys.stdin).get('data', {}).get('result', [])
    for iface in data:
        name = iface.get('name', '')
        if name == 'lo' or name.startswith('docker') or name.startswith('br-'):
            continue
        for addr in iface.get('ip-addresses', []):
            if addr.get('ip-address-type') == 'ipv4':
                ip = addr['ip-address']
                if not ip.startswith('127.') and not ip.startswith('169.254.'):
                    print(ip)
                    sys.exit(0)
except: pass
" 2>/dev/null || true)
    if [[ -n "$ip" ]]; then
      echo "    IP ${label} : ${ip}" >&2
      echo "$ip"
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
    echo "    ${elapsed}s — IP ${label} pas encore disponible..." >&2
    if [[ $elapsed -ge $timeout ]]; then
      echo "Erreur : impossible d'obtenir l'IP de ${label} après ${timeout}s." >&2
      exit 1
    fi
  done
}

# Attend que SSH réponde via Proxmox comme ProxyJump
wait_for_ssh() {
  local host="$1"
  local label="$2"
  local timeout=120
  local elapsed=0
  echo ""
  echo "==> Vérification SSH ${label} (${host})..."
  while ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
              -o "ProxyJump=root@${PROXMOX_HOST}" \
              -i "${SSH_PRIVATE_KEY_FILE}" \
              ubuntu@"${host}" "exit" 2>/dev/null; do
    sleep 5
    elapsed=$((elapsed + 5))
    echo "    ${elapsed}s — ${label} pas encore accessible..."
    if [[ $elapsed -ge $timeout ]]; then
      echo "Erreur : ${label} (${host}) inaccessible après ${timeout}s."
      exit 1
    fi
  done
  echo "    ${label} accessible en SSH."
}

wait_for_agent "${VM_ID_VAULT}"    "vault-vm"
wait_for_agent "${VM_ID_SERVICES}" "services-vm"

inject_ssh_key "${VM_ID_VAULT}"    "vault-vm"
inject_ssh_key "${VM_ID_SERVICES}" "services-vm"

VAULT_IP=$(get_vm_ip "${VM_ID_VAULT}"    "vault-vm")
SERVICES_IP=$(get_vm_ip "${VM_ID_SERVICES}" "services-vm")
export VAULT_IP SERVICES_IP

wait_for_ssh "${VAULT_IP}"    "vault-vm"
wait_for_ssh "${SERVICES_IP}" "services-vm"

echo ""
echo "==> Lancement Ansible..."
cd "$REPO_ROOT/ansible"
ansible-playbook playbooks/services-vm.yml -i inventory/onprem.py
ansible-playbook playbooks/vault.yml -i inventory/onprem.py
ansible-playbook playbooks/netbox-register.yml \
  -i inventory/onprem.py \
  -e "services_ip=${SERVICES_IP}" \
  -e "vault_ip=${VAULT_IP}"
echo ""
echo "==> Déploiement complet."

#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE_DIR="$REPO_ROOT/terraform/envs/remote"
PACKER_DIR_UBUNTU="$REPO_ROOT/packer/ubuntu-22.04"
PACKER_DIR_PFSENSE_CLOUD="$REPO_ROOT/packer/pfsense-cloud"
CONFIG_FILE="$REPO_ROOT/config.env"

# --- Vérifications ---

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Erreur : $CONFIG_FILE manquant."
  echo "  cp config.env.example config.env && éditez les valeurs"
  exit 1
fi

source "$CONFIG_FILE"

PROXMOX_HOST_REMOTE="${PROXMOX_NODE_ADDRESS_REMOTE}"
PROXMOX_API_REMOTE="https://${PROXMOX_HOST_REMOTE}:8006/api2/json"
PROXMOX_NODE_REMOTE="${PROXMOX_NODE_REMOTE:-pve}"
SSH_KEY_FILE="${SSH_PRIVATE_KEY_FILE/#\~/$HOME}"

# IPs statiques des VMs PVE2 (valeurs réseau — overridables dans config.env)
BASTION_IP="${BASTION_IP:-10.255.255.249}"
WEBSITE_IP="${WEBSITE_IP:-192.168.255.243}"

for VAR in PROXMOX_ENDPOINT_REMOTE PROXMOX_NODE_ADDRESS_REMOTE PROXMOX_PASSWORD_REMOTE \
           VM_ID_UBUNTU_TEMPLATE_REMOTE VM_ID_PFSENSE_TEMPLATE_REMOTE VM_ID_PFSENSE_REMOTE \
           VM_ID_BASTION VM_ID_WEBSITE \
           SSH_PRIVATE_KEY_FILE SSH_PUBLIC_KEY; do
  if [[ -z "${!VAR:-}" ]]; then
    echo "Erreur : ${VAR} manquant dans config.env."
    exit 1
  fi
done

# --- Fonctions ---

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
      "${PROXMOX_API_REMOTE}/nodes/${PROXMOX_NODE_REMOTE}/qemu/${vmid}/agent/ping" \
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

inject_ssh_key() {
  local vmid="$1"
  local label="$2"
  echo ""
  echo "==> Injection clé SSH dans ${label} (VM ${vmid})..."
  local tmpjson
  tmpjson=$(mktemp)
  cat > "$tmpjson" << ENDJSON
{"command":["bash","-c","mkdir -p /home/ubuntu/.ssh && echo '${SSH_PUBLIC_KEY}' > /home/ubuntu/.ssh/authorized_keys && chmod 700 /home/ubuntu/.ssh && chmod 600 /home/ubuntu/.ssh/authorized_keys && chown -R ubuntu:ubuntu /home/ubuntu/.ssh"]}
ENDJSON
  curl -s -k -X POST \
    "${PROXMOX_API_REMOTE}/nodes/${PROXMOX_NODE_REMOTE}/qemu/${vmid}/agent/exec" \
    -H "CSRFPreventionToken: ${CSRF}" \
    -b "PVEAuthCookie=${TICKET}" \
    -H "Content-Type: application/json" \
    -d "@${tmpjson}" > /dev/null
  rm -f "$tmpjson"
  sleep 5
  echo "    Clé SSH injectée dans ${label}."
}

configure_network() {
  local vmid="$1" label="$2" ip_cidr="$3" gateway="$4"
  echo ""
  echo "==> Configuration réseau ${label} (${ip_cidr}, gw ${gateway})..."
  # Netplan encodé en base64 pour éviter les problèmes d'échappement JSON/shell
  local netplan_b64
  netplan_b64=$(printf 'network:\n  version: 2\n  ethernets:\n    ens18:\n      dhcp4: false\n      addresses: [%s]\n      routes:\n        - to: default\n          via: %s\n      nameservers:\n        addresses: [1.1.1.1, 8.8.8.8]\n' \
    "${ip_cidr}" "${gateway}" | base64 -w0)
  local tmpjson
  tmpjson=$(mktemp)
  cat > "$tmpjson" << ENDJSON
{"command":["bash","-c","echo '${netplan_b64}' | base64 -d > /etc/netplan/99-static.yaml && chmod 600 /etc/netplan/99-static.yaml && netplan apply 2>/dev/null; ip addr add ${ip_cidr} dev ens18 2>/dev/null || true; ip route replace default via ${gateway} dev ens18 2>/dev/null || true"]}
ENDJSON
  curl -s -k -X POST \
    "${PROXMOX_API_REMOTE}/nodes/${PROXMOX_NODE_REMOTE}/qemu/${vmid}/agent/exec" \
    -H "CSRFPreventionToken: ${CSRF}" \
    -b "PVEAuthCookie=${TICKET}" \
    -H "Content-Type: application/json" \
    -d "@${tmpjson}" > /dev/null
  rm -f "$tmpjson"
  sleep 8
  echo "    Réseau configuré sur ${label}."
}

wait_for_ssh() {
  local host="$1"
  local label="$2"
  local timeout=120
  local elapsed=0
  echo ""
  echo "==> Vérification SSH ${label} (${host})..."
  while ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
              -o "ProxyJump=root@${PROXMOX_HOST_REMOTE}" \
              -i "${SSH_KEY_FILE}" \
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

extend_disk() {
  local host="$1"
  local label="$2"
  echo ""
  echo "==> Extension partition disque ${label} (${host})..."
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
      -o "ProxyJump=root@${PROXMOX_HOST_REMOTE}" \
      -i "${SSH_KEY_FILE}" \
      ubuntu@"${host}" "
    sudo growpart /dev/vda 3 2>/dev/null || true
    sudo pvresize /dev/vda3 2>/dev/null || true
    sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv 2>/dev/null || true
    sudo resize2fs /dev/ubuntu-vg/ubuntu-lv 2>/dev/null || true
  " 2>/dev/null || true
  echo "    Partition ${label} étendue."
}

# --- Injection clé SSH sur PVE2 ---

echo ""
echo "==> Vérification accès SSH PVE2..."
if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o PasswordAuthentication=no \
       -o BatchMode=yes -i "${SSH_KEY_FILE}" root@"${PROXMOX_HOST_REMOTE}" exit 2>/dev/null; then
  echo "    Clé SSH déjà présente sur PVE2."
else
  echo "    Clé SSH absente — injection via sshpass..."
  if ! command -v sshpass &>/dev/null; then
    echo "Erreur : sshpass non installé. sudo apt install sshpass"
    exit 1
  fi
  sshpass -p "${PROXMOX_PASSWORD_REMOTE}" ssh-copy-id \
    -o StrictHostKeyChecking=no \
    -i "${SSH_KEY_FILE}.pub" \
    root@"${PROXMOX_HOST_REMOTE}"
  echo "    Clé SSH injectée sur PVE2."
fi

# --- Auth Proxmox PVE2 ---

echo ""
echo "==> Authentification Proxmox PVE2..."
AUTH=$(curl -s -k -X POST "${PROXMOX_API_REMOTE}/access/ticket" \
  --data-urlencode "username=${PROXMOX_USER:-root@pam}" \
  --data-urlencode "password=${PROXMOX_PASSWORD_REMOTE}")

echo "    Réponse API : $(echo "$AUTH" | python3 -c "import sys,json; d=json.load(sys.stdin); print('OK' if d.get('data') else d.get('errors', d))" 2>/dev/null || echo "$AUTH")"

TICKET=$(echo "$AUTH" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['ticket'])" 2>/dev/null || true)
CSRF=$(echo "$AUTH"   | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['CSRFPreventionToken'])" 2>/dev/null || true)

if [[ -z "$TICKET" ]]; then
  echo "Erreur : authentification PVE2 échouée."
  exit 1
fi
echo "    Authentifié."

# --- Nettoyage VMs existantes ---

echo ""
echo "==> Nettoyage VMs PVE2 (${VM_ID_PFSENSE_REMOTE}, ${VM_ID_BASTION}, ${VM_ID_WEBSITE})..."
for VMID in "${VM_ID_PFSENSE_REMOTE}" "${VM_ID_BASTION}" "${VM_ID_WEBSITE}"; do
  STATUS=$(curl -s -k -b "PVEAuthCookie=${TICKET}" \
    "${PROXMOX_API_REMOTE}/nodes/${PROXMOX_NODE_REMOTE}/qemu/${VMID}/status/current" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('status','notfound'))" 2>/dev/null || echo "notfound")
  if [[ "$STATUS" != "notfound" ]]; then
    echo "    VM ${VMID} trouvée (${STATUS}), suppression..."
    if [[ "$STATUS" == "running" ]]; then
      curl -s -k -X POST "${PROXMOX_API_REMOTE}/nodes/${PROXMOX_NODE_REMOTE}/qemu/${VMID}/status/stop" \
        -H "CSRFPreventionToken: ${CSRF}" -b "PVEAuthCookie=${TICKET}" > /dev/null
      sleep 5
    fi
    curl -s -k -X DELETE "${PROXMOX_API_REMOTE}/nodes/${PROXMOX_NODE_REMOTE}/qemu/${VMID}?destroy-unreferenced-disks=1&purge=1" \
      -H "CSRFPreventionToken: ${CSRF}" -b "PVEAuthCookie=${TICKET}" > /dev/null
    echo "    VM ${VMID} supprimée."
  fi
done

# --- Bridges Cloud dédiés : vmbr3 (DMZ) et vmbr4 (LAN Cloud) ---
# vmbr1 (LAN on-prem) et vmbr2 (transit WAN pfSense) existent déjà — ne pas toucher.
# Création directement via SSH dans /etc/network/interfaces (l'API Proxmox ne persiste pas).

echo ""
echo "==> Création bridges Cloud (vmbr3=DMZ 10.255.255.248/29, vmbr4=LAN 192.168.255.240/28)..."
ssh -o StrictHostKeyChecking=no -o BatchMode=yes -i "${SSH_KEY_FILE}" root@"${PROXMOX_HOST_REMOTE}" \
  "bash -s" << 'SSHEOF'
set -euo pipefail

add_bridge() {
  local iface="$1" cidr="$2" comment="$3" nat_src="${4:-}"
  if grep -q "auto ${iface}" /etc/network/interfaces 2>/dev/null; then
    echo "    Bridge ${iface} déjà dans /etc/network/interfaces."
  else
    echo "    Ajout de ${iface} dans /etc/network/interfaces..."
    printf '\nauto %s\niface %s inet static\n\taddress %s\n\tbridge-ports none\n\tbridge-stp off\n\tbridge-fd 0\n' \
      "${iface}" "${iface}" "${cidr}" >> /etc/network/interfaces
    if [[ -n "${nat_src}" ]]; then
      printf '\tpost-up iptables -t nat -A POSTROUTING -s %s -o vmbr0 -j MASQUERADE\n' "${nat_src}" >> /etc/network/interfaces
      printf '\tpost-down iptables -t nat -D POSTROUTING -s %s -o vmbr0 -j MASQUERADE\n' "${nat_src}" >> /etc/network/interfaces
    fi
    printf '#%s\n' "${comment}" >> /etc/network/interfaces
  fi

  if ! ip link show "${iface}" &>/dev/null; then
    echo "    Activation de ${iface}..."
    ifup "${iface}" 2>/dev/null \
      || { ip link add name "${iface}" type bridge 2>/dev/null || true
           ip link set "${iface}" up
           ip addr add "${cidr}" dev "${iface}" 2>/dev/null || true; }
  else
    echo "    ${iface} déjà actif."
  fi

  if [[ -n "${nat_src}" ]]; then
    iptables -t nat -C POSTROUTING -s "${nat_src}" -o vmbr0 -j MASQUERADE 2>/dev/null \
      || iptables -t nat -A POSTROUTING -s "${nat_src}" -o vmbr0 -j MASQUERADE
  fi
}

add_bridge "vmbr3" "10.255.255.254/29" "Cloud DMZ — bastion" "10.255.255.248/29"
add_bridge "vmbr4" "192.168.255.254/28" "Cloud LAN — website + pfSense LAN"
SSHEOF
echo "    Bridges Cloud opérationnels."

# --- Packer pfSense Cloud sur PVE2 ---

echo ""
PFSENSE_CLOUD_TEMPLATE_STATUS=$(curl -s -k -b "PVEAuthCookie=${TICKET}" \
  "${PROXMOX_API_REMOTE}/nodes/${PROXMOX_NODE_REMOTE}/qemu/${VM_ID_PFSENSE_TEMPLATE_REMOTE}/status/current" 2>/dev/null | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('status','notfound'))" 2>/dev/null || echo "notfound")

if [[ "$PFSENSE_CLOUD_TEMPLATE_STATUS" == "notfound" ]]; then
  echo "==> Template pfSense Cloud (${VM_ID_PFSENSE_TEMPLATE_REMOTE}) absent — build Packer..."
  cd "$PACKER_DIR_PFSENSE_CLOUD"
  export PKR_VAR_proxmox_url="${PROXMOX_ENDPOINT_REMOTE}/api2/json"
  export PKR_VAR_proxmox_username="${PROXMOX_USER:-root@pam}"
  export PKR_VAR_proxmox_password="${PROXMOX_PASSWORD_REMOTE}"
  export PKR_VAR_proxmox_node="${PROXMOX_NODE_REMOTE}"
  export PKR_VAR_proxmox_storage_vm="${PROXMOX_STORAGE_VM_REMOTE:-local}"
  export PKR_VAR_template_vm_id="${VM_ID_PFSENSE_TEMPLATE_REMOTE}"
  export PKR_VAR_pfsense_admin_ssh_public_key="${SSH_PUBLIC_KEY}"
  packer init .
  packer build pfsense-cloud.pkr.hcl
  echo "    Template pfSense Cloud créé."
else
  echo "==> Template pfSense Cloud (${VM_ID_PFSENSE_TEMPLATE_REMOTE}) déjà présent, Packer sauté."
fi

# --- Packer Ubuntu sur PVE2 ---
# Le build se fait sur vmbr2 (DMZ 10.255.255.248/29) avec IP 10.255.255.250
# pour éviter le conflit DHCP sur le LAN Cloud 192.168.255.240/28 (trop petit)

echo ""
UBUNTU_TEMPLATE_STATUS=$(curl -s -k -b "PVEAuthCookie=${TICKET}" \
  "${PROXMOX_API_REMOTE}/nodes/${PROXMOX_NODE_REMOTE}/qemu/${VM_ID_UBUNTU_TEMPLATE_REMOTE}/status/current" 2>/dev/null | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('status','notfound'))" 2>/dev/null || echo "notfound")

if [[ "$UBUNTU_TEMPLATE_STATUS" == "notfound" ]]; then
  echo "==> Template Ubuntu (${VM_ID_UBUNTU_TEMPLATE_REMOTE}) absent sur PVE2 — build Packer..."
  cd "$PACKER_DIR_UBUNTU"
  export PKR_VAR_proxmox_url="${PROXMOX_ENDPOINT_REMOTE}/api2/json"
  export PKR_VAR_proxmox_username="${PROXMOX_USER:-root@pam}"
  export PKR_VAR_proxmox_password="${PROXMOX_PASSWORD_REMOTE}"
  export PKR_VAR_proxmox_node="${PROXMOX_NODE_REMOTE}"
  export PKR_VAR_proxmox_host="${PROXMOX_HOST_REMOTE}"
  export PKR_VAR_proxmox_storage_iso="local"
  export PKR_VAR_proxmox_storage_vm="${PROXMOX_STORAGE_VM:-local-lvm}"
  export PKR_VAR_template_vm_id="${VM_ID_UBUNTU_TEMPLATE_REMOTE}"
  export PKR_VAR_build_username="${VM_USERNAME:-ubuntu}"
  export PKR_VAR_ssh_public_key="${SSH_PUBLIC_KEY}"
  export PKR_VAR_ssh_bastion_private_key_file="${SSH_PRIVATE_KEY_FILE}"
  # Build sur DMZ (vmbr2) : évite le conflit DHCP sur le LAN Cloud (/28 trop petit)
  export PKR_VAR_packer_network_bridge="vmbr2"
  export PKR_VAR_packer_build_ip="10.255.255.250"
  export PKR_VAR_packer_build_prefix="29"
  export PKR_VAR_packer_build_gateway="10.255.255.254"
  # Password éphémère — jamais stocké
  _PACKER_PASS="$(openssl rand -base64 16 | tr -d '+/=' | head -c 20)"
  export PKR_VAR_build_password="${_PACKER_PASS}"
  export PKR_VAR_build_password_hash="$(echo "${_PACKER_PASS}" | openssl passwd -6 -stdin)"
  unset _PACKER_PASS
  packer init .
  packer build -on-error=abort ubuntu-22.04.pkr.hcl
  echo "    Template Ubuntu créé sur PVE2 — attente 30s pour déverrouillage Proxmox..."
  sleep 30
else
  echo "==> Template Ubuntu (${VM_ID_UBUNTU_TEMPLATE_REMOTE}) déjà présent sur PVE2, Packer sauté."
fi

# --- Variables Terraform communes (réutilisées dans les deux phases) ---

TF_COMMON_VARS=(
  -var "proxmox_endpoint=${PROXMOX_ENDPOINT_REMOTE}"
  -var "proxmox_password=${PROXMOX_PASSWORD_REMOTE}"
  -var "proxmox_node=${PROXMOX_NODE_REMOTE}"
  -var "proxmox_node_address=${PROXMOX_HOST_REMOTE}"
  -var "proxmox_ssh_private_key=${SSH_PRIVATE_KEY_FILE}"
  -var "vm_ssh_public_key=${SSH_PUBLIC_KEY}"
  -var "pfsense_template_id=${VM_ID_PFSENSE_TEMPLATE_REMOTE}"
  -var "pfsense_cloud_template_id=${VM_ID_PFSENSE_TEMPLATE_REMOTE}"
  -var "pfsense_vm_id=${VM_ID_PFSENSE_REMOTE}"
  -var "template_ubuntu_vm_id=${VM_ID_UBUNTU_TEMPLATE_REMOTE}"
  -var "bastion_vm_id=${VM_ID_BASTION}"
  -var "website_vm_id=${VM_ID_WEBSITE}"
  -var "storage_vm=${PROXMOX_STORAGE_VM_REMOTE:-local}"
  -var "storage_iso=${PROXMOX_STORAGE_ISO_REMOTE:-local}"
  -var "pfsense_wan_bridge=${PFSENSE_WAN_BRIDGE_REMOTE:-vmbr2}"
  -var "pfsense_lan_bridge=${PFSENSE_LAN_BRIDGE_REMOTE:-vmbr4}"
  -var "dmz_bridge=${DMZ_BRIDGE_REMOTE:-vmbr3}"
  -var "lan_bridge=${LAN_BRIDGE_REMOTE:-vmbr4}"
)

cd "$REMOTE_DIR"
terraform init -input=false -upgrade

# --- Phase 1 : pfSense (doit router avant de déployer les VMs) ---

echo ""
echo "==> Déploiement pfSense cloud (phase 1)..."
terraform apply -input=false -auto-approve \
  -target=module.pfsense \
  "${TF_COMMON_VARS[@]}"

echo "    pfSense déployé — attente 30s pour qu'il soit opérationnel..."
sleep 30

# --- Phase 2 : bastion + website ---

echo ""
echo "==> Déploiement bastion + website (phase 2)..."
terraform apply -input=false -auto-approve \
  "${TF_COMMON_VARS[@]}"

# --- QEMU agent + injection clé SSH + SSH ---

wait_for_agent "${VM_ID_BASTION}" "bastion"
wait_for_agent "${VM_ID_WEBSITE}"  "website"

inject_ssh_key "${VM_ID_BASTION}" "bastion"
inject_ssh_key "${VM_ID_WEBSITE}"  "website"

configure_network "${VM_ID_BASTION}" "bastion" "${BASTION_IP}/29" "10.255.255.254"
configure_network "${VM_ID_WEBSITE}"  "website" "${WEBSITE_IP}/28" "192.168.255.254"

wait_for_ssh "${BASTION_IP}" "bastion"
wait_for_ssh "${WEBSITE_IP}"  "website"

extend_disk "${BASTION_IP}" "bastion"
extend_disk "${WEBSITE_IP}"  "website"

echo ""
echo "==> Déploiement PVE2 complet."
echo "    bastion  : ${BASTION_IP} (DMZ 10.255.255.248/29)"
echo "    website  : ${WEBSITE_IP} (LAN Cloud 192.168.255.240/28)"
echo ""
echo "    Prochaine étape — Ansible :"
echo "      ansible-playbook playbooks/teleport.yml -i inventory/cloud.py"
echo "      ansible-playbook playbooks/website.yml  -i inventory/cloud.py"

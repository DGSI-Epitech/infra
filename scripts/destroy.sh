#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$REPO_ROOT/config.env"

# --- Vérifications ---

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Erreur : $CONFIG_FILE manquant."
  exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

PROXMOX_API="https://${PROXMOX_HOST}:8006/api2/json"
export TF_VAR_proxmox_password="${TF_VAR_proxmox_password:-${PROXMOX_PASSWORD}}"

if [[ -z "${TF_VAR_proxmox_password:-}" ]]; then
  echo "Erreur : PROXMOX_PASSWORD manquant dans config.env."
  exit 1
fi

# --- Auth Proxmox ---

echo ""
echo "==> Authentification Proxmox..."
AUTH=$(curl -s -k -X POST "${PROXMOX_API}/access/ticket" \
  --data-urlencode "username=${PROXMOX_USER}" \
  --data-urlencode "password=${TF_VAR_proxmox_password}")

TICKET=$(echo "$AUTH" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['ticket'])" 2>/dev/null || true)
CSRF=$(echo "$AUTH"   | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['CSRFPreventionToken'])" 2>/dev/null || true)

if [[ -z "$TICKET" ]]; then
  echo "Erreur : authentification Proxmox échouée."
  echo "  Réponse complète : $AUTH"
  exit 1
fi
echo "    Authentifié."

# --- Suppression ---

destroy_vm() {
  local VMID="$1"
  local STATUS

  STATUS=$(curl -s -k -b "PVEAuthCookie=${TICKET}" \
    "${PROXMOX_API}/nodes/${PROXMOX_NODE}/qemu/${VMID}/status/current" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('status','notfound'))" 2>/dev/null || echo "notfound")

  if [[ "$STATUS" == "notfound" ]]; then
    echo "    VM ${VMID} absente, rien à faire."
    return
  fi

  echo "    VM ${VMID} trouvée (${STATUS}), suppression..."
  if [[ "$STATUS" == "running" ]]; then
    curl -s -k -X POST "${PROXMOX_API}/nodes/${PROXMOX_NODE}/qemu/${VMID}/status/stop" \
      -H "CSRFPreventionToken: ${CSRF}" -b "PVEAuthCookie=${TICKET}" > /dev/null
    sleep 5
  fi
  curl -s -k -X DELETE "${PROXMOX_API}/nodes/${PROXMOX_NODE}/qemu/${VMID}?destroy-unreferenced-disks=1&purge=1" \
    -H "CSRFPreventionToken: ${CSRF}" -b "PVEAuthCookie=${TICKET}" > /dev/null
  echo "    VM ${VMID} supprimée."
}

echo ""
echo "==> Suppression des VMs..."
destroy_vm "${VM_ID_PFSENSE}"
destroy_vm "${VM_ID_SERVICES}"
destroy_vm "${VM_ID_VAULT}"

echo ""
echo "==> Suppression des templates..."
destroy_vm "${VM_ID_PFSENSE_TEMPLATE}"
destroy_vm "${VM_ID_UBUNTU_TEMPLATE}"

echo ""
echo "==> Terminé."

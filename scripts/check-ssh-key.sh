#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../config.env"

echo "==> Auth Proxmox..."
AUTH=$(curl -s -k -X POST "https://51.75.128.134:8006/api2/json/access/ticket" \
  --data-urlencode "username=root@pam" \
  --data-urlencode "password=${PROXMOX_PASSWORD}")

TICKET=$(echo "$AUTH" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['ticket'])")
CSRF=$(echo "$AUTH"   | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['CSRFPreventionToken'])")
echo "    OK"

echo ""
echo "==> Lecture authorized_keys dans vault-vm (1200)..."
RES=$(curl -s -k -X POST \
  "https://51.75.128.134:8006/api2/json/nodes/proxmox-site1/qemu/1200/agent/exec" \
  -H "CSRFPreventionToken: ${CSRF}" \
  -b "PVEAuthCookie=${TICKET}" \
  -H "Content-Type: application/json" \
  -d '{"command":["cat","/home/ubuntu/.ssh/authorized_keys"]}')

PID=$(echo "$RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['pid'])")
sleep 3

curl -s -k \
  "https://51.75.128.134:8006/api2/json/nodes/proxmox-site1/qemu/1200/agent/exec-status?pid=${PID}" \
  -b "PVEAuthCookie=${TICKET}" | python3 -c "
import sys,json
d=json.load(sys.stdin)['data']
print('EXIT CODE :', d.get('exitcode'))
print('CONTENU   :', d.get('out-data', '(vide — fichier absent)'))
print('ERREUR    :', d.get('err-data', ''))
"

echo ""
echo "==> Test SSH direct vers 172.16.0.242..."
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
    -i ~/.ssh/id_ed25519 ubuntu@172.16.0.242 echo "SSH OK" \
  && echo "    Connexion SSH réussie." \
  || echo "    Connexion SSH échouée."

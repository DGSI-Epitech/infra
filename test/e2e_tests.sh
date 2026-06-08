#!/bin/bash

# ==============================
# CONFIG
# ==============================

ELASTIC_USER="elastic"
ELASTIC_PASS="changeme"
CA_CERT="$HOME/.ansible-tls/ca.crt"

OPS_VM="ubuntu@172.16.0.242"
BASTION_VM="ubuntu@10.255.255.249"

JUMP_OP="admin@5.196.45.8"
JUMP_CLOUD="root@51.75.128.134"

WEBSITE_IP="192.168.255.243"

# ==============================
# HELPERS
# ==============================

function ok() { echo -e "\e[32m[OK]\e[0m $1"; }
function ko() { echo -e "\e[31m[KO]\e[0m $1"; }

# ==============================
# TUNNELS
# ==============================

echo "== Opening SSH tunnels =="

ssh -fNL 9200:172.16.0.242:9200 \
       -L 8200:172.16.0.242:8200 \
    -J $JUMP_OP $OPS_VM

ssh -fNL 5601:10.255.255.249:5601 \
    -J $JUMP_CLOUD $BASTION_VM

sleep 2

# ==============================
# 1. ELASTICSEARCH
# ==============================

echo "== Elasticsearch Health =="

ES_STATUS=$(curl -sk --cacert $CA_CERT -u $ELASTIC_USER:$ELASTIC_PASS https://localhost:9200/_cluster/health | grep -o '"status":"[^"]*"' | cut -d':' -f2 | tr -d '"')

if [[ "$ES_STATUS" == "yellow" || "$ES_STATUS" == "green" ]]; then
    ok "Elasticsearch health: $ES_STATUS"
else
    ko "Elasticsearch health: $ES_STATUS"
fi

# ==============================
# 2. FILEBEAT
# ==============================

echo "== Filebeat Service =="

FB_STATUS=$(ssh -J $JUMP_OP $OPS_VM "systemctl is-active filebeat")

if [[ "$FB_STATUS" == "active" ]]; then
    ok "Filebeat running on ops-vm"
else
    ko "Filebeat NOT running"
fi

# ==============================
# 3. LOG PIPELINE
# ==============================

echo "== Log Injection =="

ssh -J $JUMP_OP $OPS_VM "logger TEST_E2E_$(date +%s)"
sleep 3

LOG_FOUND=$(curl -sk --cacert $CA_CERT \
-u $ELASTIC_USER:$ELASTIC_PASS \
"https://localhost:9200/_search?q=TEST_E2E&size=1" | grep -c TEST_E2E)

if [[ "$LOG_FOUND" -gt 0 ]]; then
    ok "Logs received in Elasticsearch"
else
    ko "Logs NOT received"
fi

# ==============================
# 4. INDICES
# ==============================

echo "== Indices Check =="

INDICES=$(curl -sk --cacert $CA_CERT \
-u $ELASTIC_USER:$ELASTIC_PASS \
https://localhost:9200/_cat/indices | grep filebeat)

if [[ -n "$INDICES" ]]; then
    ok "Filebeat indices exist"
else
    ko "No filebeat indices"
fi

# ==============================
# 5. KIBANA
# ==============================

echo "== Kibana =="

KIBANA=$(curl -sk https://localhost:5601 | grep -i kibana)

if [[ -n "$KIBANA" ]]; then
    ok "Kibana accessible"
else
    ko "Kibana not accessible"
fi

# ==============================
# 6. WEBSITE ACCESS (INTERNAL)
# ==============================

echo "== Website access from bastion =="

WEB_INTERNAL=$(ssh -J $JUMP_CLOUD $BASTION_VM "curl -s -o /dev/null -w '%{http_code}' http://$WEBSITE_IP")

if [[ "$WEB_INTERNAL" == "200" ]]; then
    ok "Website reachable internally"
else
    ko "Website not reachable internally"
fi

# ==============================
# 7. WEBSITE EXTERNAL BLOCK
# ==============================

echo "== Website external security =="

WEB_EXTERNAL=$(curl -s -o /dev/null -w '%{http_code}' http://5.196.50.52)

if [[ "$WEB_EXTERNAL" == "000" || "$WEB_EXTERNAL" == "403" ]]; then
    ok "Website NOT exposed externally"
else
    ko "Website EXPOSED externally (CRITICAL)"
fi

# ==============================
# 8. VPN / CONNECTIVITY
# ==============================

echo "== VPN connectivity =="

VPN_TEST=$(ssh -J $JUMP_OP $OPS_VM "ping -c 1 $WEBSITE_IP" | grep "1 received")

if [[ -n "$VPN_TEST" ]]; then
    ok "VPN OK (inter-site connectivity)"
else
    ko "VPN DOWN"
fi

# ==============================
# 9. VAULT
# ==============================

echo "== Vault Health =="

VAULT=$(curl -sk --cacert $CA_CERT https://localhost:8200/v1/sys/health | grep -c '"sealed":false')

if [[ "$VAULT" -gt 0 ]]; then
    ok "Vault unsealed and healthy"
else
    ko "Vault sealed or down"
fi

# ==============================
# CLEANUP
# ==============================

echo "== Closing tunnels =="

fuser -k 9200/tcp 8200/tcp 5601/tcp > /dev/null 2>&1

echo "== Tests completed =="
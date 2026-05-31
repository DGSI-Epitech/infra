# Runbooks

Procédures opérationnelles pour l'infrastructure DGSI Epitech.

---

## Sommaire

1. [Déploiement Ansible](#1-déploiement-ansible)
2. [Accéder aux services via tunnel SSH](#2-accéder-aux-services-via-tunnel-ssh)
3. [Vault — init, unseal, accès](#3-vault--init-unseal-accès)
4. [Elasticsearch & Kibana](#4-elasticsearch--kibana)
5. [Filebeat](#5-filebeat)
6. [Gestion du disque](#6-gestion-du-disque)
7. [Diagnostics SSH](#7-diagnostics-ssh)
8. [Résolution de problèmes](#8-résolution-de-problèmes)

---

## 1. Déploiement Ansible

### Toujours depuis `ansible/`

```bash
cd ansible/
```

Le `ansible.cfg` est dans ce répertoire — les playbooks ne fonctionnent pas depuis la racine du repo.

### Vérifier la connectivité

```bash
ansible all -m ping
# services-vm est hors ligne → UNREACHABLE attendu
```

### Ordre de déploiement

```bash
# 1. Certificats TLS (à faire en premier, avant tout autre service)
ansible-playbook playbooks/tls.yml

# 2. Vault (ops-vm)
ansible-playbook playbooks/vault.yml

# 3. Elasticsearch (ops-vm)
ansible-playbook playbooks/elk.yml

# 4. Kibana (bastion)
ansible-playbook playbooks/kibana.yml

# 5. Filebeat (ops-vm + bastion)
ansible-playbook playbooks/filebeat.yml

# 6. pfSense (firewall, VPN, DNS)
ansible-playbook playbooks/pfsense.yml --tags configure
```

### Variables

Toutes les variables viennent de `../config.env` (lu par l'inventaire dynamique `inventory/onprem.py`).

Variables critiques :
```
VM_IP_OPS="172.16.255.253/28"
VM_IP_BASTION="10.255.255.253/29"
VM_IP_WEB="192.168.255.253/28"
PFSENSE_OP_WAN="5.196.45.8"
PFSENSE_CLOUD_WAN="5.196.50.52"
```

---

## 2. Accéder aux services via tunnel SSH

Tous les services sont sur des réseaux privés. Il faut ouvrir des tunnels SSH via pfSense.

### Tunnels PVE1 (Elasticsearch, Vault — via pfSense-OP)

```bash
ssh -fNL 9200:172.16.255.253:9200 \
       -L 8200:172.16.255.253:8200 \
    -J admin@5.196.45.8 dgsi-op@172.16.255.253
```

### Tunnels PVE2 (Kibana — via pfSense-Cloud)

```bash
ssh -fNL 5601:10.255.255.253:5601 \
    -J admin@5.196.50.52 dgsi-cloud@10.255.255.253
```

### Fermer les tunnels

```bash
fuser -k 9200/tcp 8200/tcp 5601/tcp
```

### URLs d'accès (après tunnel ouvert)

| Service | URL | Credentials |
|---------|-----|-------------|
| Kibana | https://localhost:5601 | elastic / `elk_elastic_password` |
| Vault | https://localhost:8200 | root token dans `/root/vault-init.json` |
| Elasticsearch | https://localhost:9200 | elastic / `elk_elastic_password` |

**Note TLS :** Le certificat est signé par la DGSI Internal CA. Importer `~/.ansible-tls/ca.crt` dans le navigateur pour éviter l'avertissement.

---

## 3. Vault — init, unseal, accès

### Vérifier l'état

```bash
curl -sk --cacert ~/.ansible-tls/ca.crt https://localhost:8200/v1/sys/health | python3 -m json.tool
```

Champs attendus : `"initialized": true`, `"sealed": false`

### Unseal après redémarrage

Vault se scelle à chaque redémarrage du container. Le playbook `vault.yml` unseal automatiquement en lisant `/root/vault-init.json` sur ops-vm.

Pour unseal manuellement :

```bash
ansible-playbook playbooks/vault.yml
```

Ou via curl :

```bash
# Lire les clés (tunnel SSH ouvert vers ops-vm)
ansible ops -m shell -a "cat /root/vault-init.json" --become | grep keys_base64 -A 5

# Unseal (3 clés requises)
curl -sk --cacert ~/.ansible-tls/ca.crt -X PUT https://localhost:8200/v1/sys/unseal \
  -d '{"key": "<UNSEAL_KEY_1>"}' | python3 -m json.tool
```

### Récupérer le root token

```bash
ansible ops -m shell -a "cat /root/vault-init.json" --become | python3 -m json.tool
```

---

## 4. Elasticsearch & Kibana

### Vérifier la santé ES

```bash
curl -sk --cacert ~/.ansible-tls/ca.crt \
  -u elastic:changeme \
  https://localhost:9200/_cluster/health | python3 -m json.tool
```

`yellow` est normal en single-node (replica non assignable).

### Vérifier les indices Filebeat

```bash
curl -sk --cacert ~/.ansible-tls/ca.crt \
  -u elastic:changeme \
  https://localhost:9200/_cat/indices?v
```

### Politique ILM Filebeat

```bash
curl -sk --cacert ~/.ansible-tls/ca.crt \
  -u elastic:changeme \
  https://localhost:9200/_ilm/policy/filebeat-policy | python3 -m json.tool
```

Paramètres : rollover 1GB/7j, delete après 30j.

### Redémarrer Elasticsearch

```bash
ansible ops -m shell -a "docker compose -f /opt/elk/docker-compose.yml restart elasticsearch" --become
```

### Redémarrer Kibana

```bash
ansible bastion -m shell -a "docker compose -f /opt/kibana/docker-compose.yml restart kibana" --become
```

---

## 5. Filebeat

### Vérifier le statut

```bash
ansible ops:bastion -m shell -a "systemctl status filebeat --no-pager | grep -E 'Active:|Loaded:'"
```

### Forcer un rechargement

```bash
ansible ops:bastion -m shell -a "systemctl restart filebeat"
```

### Vérifier que les logs arrivent dans ES

```bash
curl -sk --cacert ~/.ansible-tls/ca.crt \
  -u elastic:changeme \
  "https://localhost:9200/_cat/indices?v&h=index,docs.count,store.size"
```

L'index `.ds-filebeat-*` doit avoir un `docs.count` > 0.

---

## 6. Gestion du disque

### État du disque sur toutes les VMs

```bash
ansible ops:bastion:web -m shell -a "df -h /"
```

### Nettoyage d'urgence (libère 200MB–1GB)

```bash
# Cache apt + logs journal
ansible ops:bastion -m shell -a "apt-get clean -y && journalctl --vacuum-size=50M" --become

# Cache Docker (containers/images non utilisés)
ansible ops:bastion -m shell -a "docker system prune -f" --become
```

### Taille des données ES

```bash
ansible ops -m shell -a "du -sh /opt/elk/elasticsearch/data/"
```

### Espace Docker par image

```bash
ansible ops:bastion -m shell -a "docker images"
```

---

## 7. Diagnostics SSH

### Tester la connectivité pfSense

```bash
ssh admin@5.196.45.8 echo "pfSense-OP OK"
ssh admin@5.196.50.52 echo "pfSense-Cloud OK"
```

### Tester l'accès à une VM via ProxyJump

```bash
# ops-vm
ssh -J admin@5.196.45.8 dgsi-op@172.16.255.253 echo "ops-vm OK"

# bastion
ssh -J admin@5.196.50.52 dgsi-cloud@10.255.255.253 echo "bastion OK"
```

### Si pfSense refuse le forwarding TCP

Vérifier dans le webGUI pfSense que SSH est bien activé :
- pfSense-OP : https://5.196.45.8 (admin / `PFSENSE_PASSWORD`)
- pfSense-Cloud : https://5.196.50.52

Menu : System > Advanced > Admin Access > Secure Shell = Enabled.

---

## 8. Résolution de problèmes

### Elasticsearch ne démarre pas — `vm.max_map_count`

```bash
ansible ops -m shell -a "sysctl vm.max_map_count"
# Doit retourner vm.max_map_count = 262144
ansible ops -m sysctl -a "name=vm.max_map_count value=262144 state=present reload=yes" --become
```

### Kibana — `Kibana server is not ready yet`

Kibana attend qu'Elasticsearch soit disponible. Attendre ~2-3 min après démarrage.
Vérifier les logs :

```bash
ansible bastion -m shell -a "docker logs kibana --tail 30" --become
```

Si Kibana ne peut pas joindre ES, vérifier que le tunnel VPN est actif (OpenVPN entre pfSense-OP et pfSense-Cloud).

### Vault scellé après redémarrage

```bash
ansible-playbook playbooks/vault.yml
```

Le playbook détecte l'état sealed et unseal automatiquement.

### `no space left on device`

Disk plein. Nettoyer le cache :

```bash
ansible ops:bastion -m shell -a "apt-get clean -y && journalctl --vacuum-size=50M && docker system prune -f" --become
```

Si insuffisant : les images Docker occupent la majorité de l'espace (ES: 1.88GB, Vault: 612MB, Kibana: 1.73GB). La solution à long terme est d'augmenter le disque des VMs via Proxmox.

### Filebeat — erreur de connexion à Elasticsearch

Vérifier que le CA cert est bien présent sur la VM :

```bash
ansible ops:bastion -m shell -a "ls -la /etc/ssl/internal/"
```

Si absent, rejouer le TLS playbook :

```bash
ansible-playbook playbooks/tls.yml
```

### SSH timeout vers une VM

Les VMs sont sur réseaux privés — connexion directe impossible. Toujours passer par ProxyJump pfSense.

Vérifier que pfSense est joignable :

```bash
ssh admin@5.196.45.8 echo "OK"  # pfSense-OP
ssh admin@5.196.50.52 echo "OK" # pfSense-Cloud
```

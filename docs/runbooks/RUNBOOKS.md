# Runbooks

Procédures et résolution de problèmes pour l'infrastructure on-premise.

---

## Sommaire

1. [Premier déploiement](#1-premier-déploiement)
2. [Déploiement courant](#2-déploiement-courant)
3. [Ansible manuellement](#3-ansible-manuellement)
4. [Accéder à Vault](#4-accéder-à-vault)
5. [Accéder à Kibana / ELK](#5-accéder-à-kibana--elk)
6. [Diagnostics SSH](#6-diagnostics-ssh)
7. [Résolution de problèmes](#7-résolution-de-problèmes)
8. [Fleet Server et Elastic Agents](#8-fleet-server-et-elastic-agents)

---

## 1. Premier déploiement

### 1.1 Préparer la paire de clés SSH

L'infrastructure n'utilise **aucun password** pour accéder aux VMs. Une unique paire de clés ED25519 couvre tous les accès : Packer bastion, Terraform provider bpg, injection QEMU agent, Ansible.

```bash
# Générer la paire de clés si elle n'existe pas
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "lab-infra"

# Copier la clé publique sur Proxmox (requis pour Packer bastion + Terraform bpg provider)
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@<PROXMOX_HOST>

# Ajouter la clé à l'agent SSH pour la session
ssh-add ~/.ssh/id_ed25519

# Vérifier la connexion
ssh root@<PROXMOX_HOST> echo "OK"
```

### 1.2 Configurer config.env

```bash
cp config.env.example config.env
```

Remplir toutes les valeurs :

```bash
PROXMOX_HOST="51.75.128.134"
PROXMOX_USER="root@pam"
PROXMOX_PASSWORD="..."           # Mot de passe root Proxmox (API curl uniquement)
PROXMOX_NODE="proxmox-site1"
PROXMOX_STORAGE_VM="local"

VM_ID_UBUNTU_TEMPLATE=1000
VM_ID_PFSENSE_TEMPLATE=2000
VM_ID_PFSENSE=2100
VM_ID_SERVICES=2300
VM_ID_OPS=2200

VM_IP_SERVICES="172.16.0.241/24"   # fallback si OPS_IP non exporté
VM_IP_OPS="172.16.0.242/24"        # fallback si SERVICES_IP non exporté
VM_GATEWAY="172.16.0.254"

# SSH
SSH_PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)"
SSH_PRIVATE_KEY_FILE="~/.ssh/id_ed25519"

VM_USERNAME="ubuntu"
```

Pour connaître le nom du nœud Proxmox :

```bash
curl -s -k -X POST "https://<IP>:8006/api2/json/access/ticket" \
  -d "username=root@pam&password=<PASSWORD>" | python3 -m json.tool
```

### 1.3 Déployer

```bash
npm run deploy
```

Le script fait dans l'ordre :
1. Auth API Proxmox
2. Nettoyage des VMs existantes (pas les templates)
3. Vérification/création du bridge `vmbr1`
4. Build Packer pfSense si le template est absent (~3 min)
5. Terraform pfSense + attente 30s
6. Build Packer Ubuntu si le template est absent (~25 min)
7. Terraform ops-vm + services-vm
8. Attente QEMU agent + injection clé SSH via API
9. Vérification SSH via ProxyJump Proxmox
10. Extension partition disque (growpart + LVM resize)
11. Ansible : Vault, ELK stack, Filebeat

Durée totale : **~35 min** (premiers builds) / **~10 min** (templates déjà présents)

---

## 2. Déploiement courant

```bash
ssh-add ~/.ssh/id_ed25519   # si nouvelle session terminal
npm run deploy
```

Ansible se lance automatiquement à la fin. Pour tout supprimer :

```bash
npm run destroy
```

---

## 3. Ansible manuellement

L'inventaire est un script Python dynamique qui lit `config.env`. Les IPs et le ProxyJump SSH sont toujours cohérents avec la configuration courante.

```bash
cd ansible

# Vérifier l'inventaire généré
python3 inventory/onprem.py --list | python3 -m json.tool

# Déployer Vault uniquement
ansible-playbook playbooks/vault.yml -i inventory/onprem.py

# Déployer ELK + Fleet Server uniquement
ansible-playbook playbooks/elk.yml -i inventory/onprem.py

# Déployer Elastic Agents uniquement
ansible-playbook playbooks/elastic-agent.yml -i inventory/onprem.py

# Tout redéployer dans l'ordre
npm run ansible:all
```

Si tu relances Ansible sans `deploy.sh`, l'inventaire ne connaît pas les IPs dynamiques. Exporte-les à la main ou assure-toi que `VM_IP_OPS` et `VM_IP_SERVICES` sont dans `config.env` :

```bash
export OPS_IP=172.16.0.242
export SERVICES_IP=172.16.0.241
ansible-playbook playbooks/elk.yml -i inventory/onprem.py
```

---

## 4. Accéder à Vault

Vault tourne sur `ops-vm` (`172.16.0.242`) port `8200`, sur le réseau privé `vmbr1`. Inaccessible directement — il faut un tunnel SSH via Proxmox.

### 4.1 Ouvrir le tunnel SSH

Dans un terminal dédié (à laisser ouvert) :

```bash
ssh -L 8200:172.16.0.242:8200 -N -i ~/.ssh/id_ed25519 root@51.75.128.134
```

Puis ouvrir dans le navigateur :

```
http://localhost:8200
```

### 4.2 Vérifier l'état de Vault

```bash
ssh -o ProxyJump=root@51.75.128.134 -i ~/.ssh/id_ed25519 ubuntu@172.16.0.242 \
  "export VAULT_ADDR=http://127.0.0.1:8200 && vault status"
```

Champs importants dans la réponse :

| Champ | Valeur attendue | Signification |
|---|---|---|
| `Initialized` | `true` | Vault a été initialisé |
| `Sealed` | `false` | Vault est opérationnel |
| `HA Enabled` | `false` | Mode single-node (Raft) |

### 4.3 Unseal Vault après redémarrage

Vault se scelle à chaque redémarrage. Il faut 3 des 5 unseal keys (sauvegardées dans `/root/vault-init.json`) :

```bash
ssh -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.242 \
  "sudo cat /root/vault-init.json | python3 -m json.tool"
```

Puis unseal :

```bash
ssh -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.242 \
  "export VAULT_ADDR=http://127.0.0.1:8200 && vault operator unseal <UNSEAL_KEY>"
# Répéter 3 fois avec 3 clés différentes
```

### 4.4 Se connecter à l'UI

Ouvrir `http://localhost:8200` (tunnel ouvert) et se connecter avec le **root token** (`hvs.xxxx`).

---

## 5. Accéder à Kibana / ELK

ELK tourne sur `ops-vm` via Docker Compose. Kibana (port 5601) et Elasticsearch (port 9200) sont sur le réseau privé `vmbr1` — il faut un tunnel SSH.

### 5.1 Ouvrir le tunnel SSH

Dans un terminal dédié (à laisser ouvert) :

```bash
ssh -N -L 5601:172.16.0.242:5601 -L 9200:172.16.0.242:9200 -i ~/.ssh/id_ed25519 -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.242
```

Puis ouvrir dans le navigateur : **http://localhost:5601**

### 5.2 Vérifier l'état des containers ELK

```bash
ssh -o ProxyJump=root@51.75.128.134 -i ~/.ssh/id_ed25519 ubuntu@172.16.0.242 \
  "docker compose -f /opt/elk/docker-compose.yml ps"
```

Tous les services doivent être `running (healthy)`.

### 5.3 Vérifier la santé Elasticsearch

```bash
curl -s http://localhost:9200/_cluster/health?pretty
```

```json
{
  "cluster_name": "lab-elk",
  "status": "yellow",    ← normal en single-node (replica non assignable)
  "number_of_nodes": 1,
  "active_shards": 29,
  "unassigned_shards": 1  ← replica du seul index, ne peut pas s'allouer sur 1 nœud
}
```

`yellow` est normal en single-node. `red` indique un problème de données.

### 5.4 Vérifier que Filebeat envoie des logs

```bash
curl -s http://localhost:9200/_cat/indices?v
```

Un index `filebeat-*` doit apparaître avec un `docs.count` croissant.

### 5.5 Créer une Data View dans Kibana

1. Kibana → **Management → Stack Management → Data Views**
2. **Create data view**
3. Name : `filebeat-*`, Index pattern : `filebeat-*`, Timestamp field : `@timestamp`
4. **Save** puis aller dans **Discover** pour voir les logs de `services-vm`

### 5.6 Redémarrer ELK

```bash
ssh -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.242 \
  "docker compose -f /opt/elk/docker-compose.yml restart"
```

Ou pour forcer une recréation des containers (après changement de config) :

```bash
ansible-playbook playbooks/elk.yml -i inventory/onprem.py
```

---

## 6. Diagnostics SSH

### Vérifier la clé SSH dans une VM via QEMU agent

```bash
source config.env
AUTH=$(curl -s -k -X POST "https://${PROXMOX_HOST}:8006/api2/json/access/ticket" \
  -d "username=root@pam&password=${PROXMOX_PASSWORD}")
TICKET=$(echo "$AUTH" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['ticket'])")
CSRF=$(echo "$AUTH"   | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['CSRFPreventionToken'])")

# Remplacer 2200 par l'ID VM souhaité
RES=$(curl -s -k -X POST "https://${PROXMOX_HOST}:8006/api2/json/nodes/${PROXMOX_NODE}/qemu/2200/agent/exec" \
  -H "CSRFPreventionToken: ${CSRF}" -b "PVEAuthCookie=${TICKET}" \
  -H "Content-Type: application/json" \
  -d '{"command":["cat","/home/ubuntu/.ssh/authorized_keys"]}')
PID=$(echo "$RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['pid'])")
sleep 3
curl -s -k "https://${PROXMOX_HOST}:8006/api2/json/nodes/${PROXMOX_NODE}/qemu/2200/agent/exec-status?pid=${PID}" \
  -b "PVEAuthCookie=${TICKET}" | python3 -c \
  "import sys,json; d=json.load(sys.stdin)['data']; print('EXIT:', d.get('exitcode')); print('KEY:', d.get('out-data','(vide)'))"
```

Ou utiliser le script de diagnostic dédié :

```bash
bash scripts/check-ssh-key.sh
```

### Tester SSH manuellement (via ProxyJump)

```bash
source config.env
ssh -o StrictHostKeyChecking=no -o ProxyJump=root@${PROXMOX_HOST} \
    -i ~/.ssh/id_ed25519 ubuntu@172.16.0.242 echo "OK"
```

### Ré-injecter la clé SSH manuellement

Si la clé a disparu d'une VM après un redéploiement partiel :

```bash
source config.env
AUTH=$(curl -s -k -X POST "https://${PROXMOX_HOST}:8006/api2/json/access/ticket" \
  -d "username=root@pam&password=${PROXMOX_PASSWORD}")
TICKET=$(echo "$AUTH" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['ticket'])")
CSRF=$(echo "$AUTH"   | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['CSRFPreventionToken'])")

curl -s -k -X POST "https://${PROXMOX_HOST}:8006/api2/json/nodes/${PROXMOX_NODE}/qemu/2200/agent/exec" \
  -H "CSRFPreventionToken: ${CSRF}" -b "PVEAuthCookie=${TICKET}" \
  -H "Content-Type: application/json" \
  -d "{\"command\":[\"bash\",\"-c\",\"mkdir -p /home/ubuntu/.ssh && echo '${SSH_PUBLIC_KEY}' > /home/ubuntu/.ssh/authorized_keys && chmod 700 /home/ubuntu/.ssh && chmod 600 /home/ubuntu/.ssh/authorized_keys && chown -R ubuntu:ubuntu /home/ubuntu/.ssh\"]}"
```

---

## 7. Résolution de problèmes

### `no space left on device` — images Docker ELK

Les images ELK pèsent ~4-5 Go. Si le filesystem est plein à 8 Go, le pull échoue.

Vérifier l'espace disque :
```bash
ssh -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.242 "df -h /"
```

Si `/` affiche 8 Go au lieu de 30 Go, la partition n'a pas été étendue. L'étendre manuellement :

```bash
ssh -o ProxyJump=root@51.75.128.134 -i ~/.ssh/id_ed25519 ubuntu@172.16.0.242 "
  sudo growpart /dev/vda 3
  sudo pvresize /dev/vda3
  sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
  sudo resize2fs /dev/ubuntu-vg/ubuntu-lv
  df -h /
"
```

Puis relancer ELK :
```bash
ansible-playbook playbooks/elk.yml -i inventory/onprem.py
```

`deploy.sh` fait maintenant cette extension automatiquement avant Ansible — ce problème ne survient qu'en cas de relance manuelle après un déploiement partiel.

### Elasticsearch status `red`

```bash
curl -s http://localhost:9200/_cluster/health?pretty
curl -s http://localhost:9200/_cat/shards?v | grep UNASSIGNED
```

Cause probable : l'index a des shards primaires non assignés (données corrompues ou volume manquant).

Fix : vérifier les logs du container ES.
```bash
ssh -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.242 \
  "docker logs elasticsearch --tail 50"
```

### Kibana — `Kibana server is not ready yet`

Kibana attend qu'Elasticsearch soit `green` avant de démarrer. Attendre ~2-3 min après le démarrage du Compose. Si ça persiste :

```bash
ssh -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.242 \
  "docker logs kibana --tail 30"
```

### Elastic Agent — pas de données dans Elasticsearch

1. Vérifier que elastic-agent tourne sur `services-vm` :
```bash
ssh -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.241 \
  "sudo elastic-agent status"
```

2. Vérifier la connectivité vers Fleet Server (port 8220) :
```bash
ssh -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.241 \
  "nc -zv 172.16.0.242 8220"
```

3. Vérifier les logs Elastic Agent :
```bash
ssh -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.241 \
  "sudo journalctl -u elastic-agent -n 50"
```

### Packer Ubuntu — SSH auth failed (publickey)

```
ssh: handshake failed: ssh: unable to authenticate, attempted methods [none publickey]
```

Packer arrive à la VM via le bastion mais la clé est rejetée. Causes possibles :

1. **Le bastion n'a pas la clé** : vérifier que `ssh-copy-id` a été fait sur Proxmox
2. **`SSH_PRIVATE_KEY_FILE` ne correspond pas à `SSH_PUBLIC_KEY`** dans `config.env` : les deux doivent être la même paire
3. **`SSH_PRIVATE_KEY_FILE` non défini** dans `config.env` : le script affiche une erreur de validation au démarrage

### Permission denied (publickey) sur ops-vm ou services-vm

La clé SSH n'est pas dans `authorized_keys`. Cloud-init ne l'injecte pas pour les users créés par autoinstall.

Fix : ré-injecter via QEMU agent (voir section 6 ci-dessus), ou relancer `npm run deploy`.

### SSH timeout vers 172.16.0.x

Les VMs sont sur `vmbr1` (réseau privé). Connexion directe impossible depuis l'extérieur.

Toujours passer par le ProxyJump :
```bash
ssh -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.x ...
```

### Ansible — provided hosts list is empty

```
[WARNING]: provided hosts list is empty, only localhost is available.
```

L'inventaire utilisé est l'ancien fichier YAML (`onprem.yml`) ou le script Python renvoie un mauvais format.

Utiliser le script dynamique :
```bash
ansible-playbook ... -i inventory/onprem.py
```

Vérifier que le script retourne bien les hosts :
```bash
python3 inventory/onprem.py --list | python3 -m json.tool
```

### Script s'arrête après "Authentification Proxmox..."

`curl` échoue silencieusement à cause de `set -euo pipefail`.

Test manuel :
```bash
source config.env
curl -s -k -X POST "https://${PROXMOX_HOST}:8006/api2/json/access/ticket" \
  -d "username=${PROXMOX_USER}&password=${PROXMOX_PASSWORD}" | python3 -m json.tool
```

### Packer — KVM virtualisation not available

```
Error starting VM: KVM virtualisation configured, but not available.
```

Proxmox tourne dans une VM VMware sans virtualisation imbriquée. Fix appliqué : `disable_kvm = true` dans `pfsense-2.7.pkr.hcl`. Le build est plus lent (~15 min) mais fonctionne.

### Terraform — timeout QEMU agent

```
Warning: timeout while waiting for the QEMU agent on VM "2200" to publish the network interfaces
```

Warning non bloquant. Le QEMU agent se lance après le timeout Terraform, mais il est bien disponible quand `deploy.sh` l'attend dans l'étape suivante (`wait_for_agent`).

### State lock bloqué

```
Error: Error acquiring the state lock
```

```bash
ps aux | grep terraform
kill <PID>
rm terraform/envs/onprem/terraform.tfstate.lock.info
```

### VMs en statut io-error

Le pool de stockage est plein.

```bash
ssh root@$PROXMOX_HOST pvesm status
npm run destroy  # libère l'espace
```

---

## 8. Fleet Server et Elastic Agents

### 8.1 Vérifier que Fleet Server tourne

```bash
ssh -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.242 \
  "docker compose -f /opt/elk/docker-compose.yml ps fleet-server"
```

Le container doit être `running`. S'il est en `restarting`, vérifier les logs :

```bash
ssh -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.242 \
  "docker logs fleet-server --tail 50"
```

### 8.2 Vérifier que le token est dans Vault

```bash
ssh -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.242 \
  "VAULT_TOKEN=\$(sudo cat /root/vault-init.json | python3 -c \"import sys,json; print(json.load(sys.stdin)['root_token'])\") && \
   curl -s -H \"X-Vault-Token: \$VAULT_TOKEN\" \
   http://127.0.0.1:8200/v1/secret/data/elk/fleet-enrollment-token | python3 -m json.tool"
```

### 8.3 Vérifier les agents enrôlés

Via tunnel SSH (voir section 5.1) puis ouvrir **http://localhost:5601** → Fleet → Agents.

Les deux agents (ops-vm et services-vm) doivent apparaître en statut **Healthy**.

### 8.4 Statut Elastic Agent sur une VM

```bash
# Sur ops-vm
ssh -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.242 \
  "sudo elastic-agent status"

# Sur services-vm
ssh -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.241 \
  "sudo elastic-agent status"
```

### 8.5 Ré-enrôler un agent manuellement

Si un agent est désynchronisé de Fleet, relancer le playbook :

```bash
cd ansible
export OPS_IP=172.16.0.242
export SERVICES_IP=172.16.0.241
ansible-playbook playbooks/elastic-agent.yml -i inventory/onprem.py
```

Le playbook vérifie le statut avant d'enrôler — si l'agent est déjà `Healthy`, l'étape est sautée.

### 8.6 Fleet Server — enrollment token vide au premier déploiement

Si Kibana n'a pas fini d'initialiser Fleet quand le rôle ELK récupère le token, la liste retournée est vide. Le rôle retente avec `retries: 10` / `delay: 10`. Si ça persiste après le délai :

```bash
# Relancer uniquement le playbook ELK pour retenter la récupération du token
cd ansible
export OPS_IP=172.16.0.242
ansible-playbook playbooks/elk.yml -i inventory/onprem.py
```

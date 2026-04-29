# Runbooks

Procédures et résolution de problèmes pour l'infrastructure on-premise.

---

## Sommaire

1. [Premier déploiement](#1-premier-déploiement)
2. [Déploiement courant](#2-déploiement-courant)
3. [Ansible manuellement](#3-ansible-manuellement)
4. [Accéder à Vault](#4-accéder-à-vault)
5. [Diagnostics SSH](#5-diagnostics-ssh)
6. [Résolution de problèmes](#6-résolution-de-problèmes)

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
VM_ID_SERVICES=1100
VM_ID_VAULT=1200

VM_IP_SERVICES="172.16.0.241/24"
VM_IP_VAULT="172.16.0.242/24"
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
7. Terraform vault-vm + services-vm
8. Attente QEMU agent + injection clé SSH via API
9. Vérification SSH via ProxyJump Proxmox
10. Ansible : install Vault, init, unseal

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

# Déployer Vault
ansible-playbook playbooks/vault.yml -i inventory/onprem.py

# Déployer services-vm
ansible-playbook playbooks/services-vm.yml -i inventory/onprem.py
```

Les VMs étant sur `vmbr1` (réseau privé derrière pfSense), toutes les connexions Ansible passent automatiquement par Proxmox comme ProxyJump SSH.

Vérifier que Vault est opérationnel :

```bash
# Via ProxyJump
ssh -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.242 \
  "export VAULT_ADDR=http://127.0.0.1:8200 && vault status"
```

---

## 4. Accéder à Vault

Vault tourne sur `vault-vm` (`172.16.0.242`) port `8200`, sur le réseau privé `vmbr1`. Inaccessible directement — il faut un tunnel SSH via Proxmox.

### 4.1 Ouvrir le tunnel SSH

Dans un terminal dédié (à laisser ouvert) :

```bash
ssh -L 8200:172.16.0.242:8200 -N root@51.75.128.134
```

Puis ouvrir dans le navigateur :

```
http://localhost:8200
```

### 4.2 Vérifier l'état de Vault

```bash
ssh -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.242 \
  "export VAULT_ADDR=http://127.0.0.1:8200 && vault status"
```

Champs importants dans la réponse :

| Champ | Valeur attendue | Signification |
|---|---|---|
| `Initialized` | `true` | Vault a été initialisé |
| `Sealed` | `false` | Vault est opérationnel |
| `HA Enabled` | `false` | Mode single-node (Raft) |

### 4.3 Initialiser Vault (première fois uniquement)

Si `Initialized: false` :

```bash
ssh -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.242 \
  "export VAULT_ADDR=http://127.0.0.1:8200 && vault operator init"
```

La commande retourne :

```
Unseal Key 1: xxxx
Unseal Key 2: xxxx
Unseal Key 3: xxxx
Unseal Key 4: xxxx
Unseal Key 5: xxxx

Initial Root Token: hvs.xxxx
```

**Sauvegarder ces valeurs immédiatement.** Sans les unseal keys, les données Vault sont irrécupérables si la VM redémarre.

Les unseal keys sont également sauvegardées automatiquement dans `/root/vault-init.json` sur `vault-vm` par le role Ansible.

### 4.4 Unseal Vault

Vault se scelle à chaque redémarrage. Il faut 3 des 5 unseal keys pour le déverrouiller :

```bash
ssh -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.242 \
  "export VAULT_ADDR=http://127.0.0.1:8200 && vault operator unseal <UNSEAL_KEY_1>"

ssh -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.242 \
  "export VAULT_ADDR=http://127.0.0.1:8200 && vault operator unseal <UNSEAL_KEY_2>"

ssh -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.242 \
  "export VAULT_ADDR=http://127.0.0.1:8200 && vault operator unseal <UNSEAL_KEY_3>"
```

Après la 3ème clé, `Sealed` passe à `false` — Vault est opérationnel.

### 4.5 Se connecter à l'UI

Ouvrir `http://localhost:8200` (tunnel ouvert) et se connecter avec le **root token** (`hvs.xxxx`).

Pour les usages quotidiens, créer un token limité plutôt que d'utiliser le root token :

```bash
ssh -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.242 "
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=<ROOT_TOKEN>
vault token create -policy=default -ttl=8h
"
```

### 4.6 Lire les unseal keys sauvegardées

```bash
ssh -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.242 \
  "sudo cat /root/vault-init.json | python3 -m json.tool"
```

---

## 5. Diagnostics SSH

### Vérifier la clé SSH dans une VM via QEMU agent

```bash
source config.env
AUTH=$(curl -s -k -X POST "https://${PROXMOX_HOST}:8006/api2/json/access/ticket" \
  -d "username=root@pam&password=${PROXMOX_PASSWORD}")
TICKET=$(echo "$AUTH" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['ticket'])")
CSRF=$(echo "$AUTH"   | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['CSRFPreventionToken'])")

# Remplacer 1200 par l'ID VM souhaité
RES=$(curl -s -k -X POST "https://${PROXMOX_HOST}:8006/api2/json/nodes/${PROXMOX_NODE}/qemu/1200/agent/exec" \
  -H "CSRFPreventionToken: ${CSRF}" -b "PVEAuthCookie=${TICKET}" \
  -H "Content-Type: application/json" \
  -d '{"command":["cat","/home/ubuntu/.ssh/authorized_keys"]}')
PID=$(echo "$RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['pid'])")
sleep 3
curl -s -k "https://${PROXMOX_HOST}:8006/api2/json/nodes/${PROXMOX_NODE}/qemu/1200/agent/exec-status?pid=${PID}" \
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

# Remplacer 1200 et SSH_PUBLIC_KEY par les valeurs correctes
curl -s -k -X POST "https://${PROXMOX_HOST}:8006/api2/json/nodes/${PROXMOX_NODE}/qemu/1200/agent/exec" \
  -H "CSRFPreventionToken: ${CSRF}" -b "PVEAuthCookie=${TICKET}" \
  -H "Content-Type: application/json" \
  -d "{\"command\":[\"bash\",\"-c\",\"mkdir -p /home/ubuntu/.ssh && echo '${SSH_PUBLIC_KEY}' > /home/ubuntu/.ssh/authorized_keys && chmod 700 /home/ubuntu/.ssh && chmod 600 /home/ubuntu/.ssh/authorized_keys && chown -R ubuntu:ubuntu /home/ubuntu/.ssh\"]}"
```

---

## 6. Résolution de problèmes

### Packer Ubuntu — SSH auth failed (publickey)

```
ssh: handshake failed: ssh: unable to authenticate, attempted methods [none publickey]
```

Packer arrive à la VM via le bastion mais la clé est rejetée. Causes possibles :

1. **Le bastion n'a pas la clé** : vérifier que `ssh-copy-id` a été fait sur Proxmox
2. **`SSH_PRIVATE_KEY_FILE` ne correspond pas à `SSH_PUBLIC_KEY`** dans `config.env` : les deux doivent être la même paire
3. **`SSH_PRIVATE_KEY_FILE` non défini** dans `config.env` : le script affiche une erreur de validation au démarrage

### Permission denied (publickey) sur vault-vm ou services-vm

La clé SSH n'est pas dans `authorized_keys`. Cloud-init ne l'injecte pas pour les users créés par autoinstall.

Fix : ré-injecter via QEMU agent (voir section 4 ci-dessus), ou relancer `npm run deploy`.

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
Warning: timeout while waiting for the QEMU agent on VM "1200" to publish the network interfaces
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

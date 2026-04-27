# Runbooks

Procédures et résolution de problèmes pour l'infrastructure on-premise.

---

## Sommaire

1. [Premier déploiement](#1-premier-déploiement)
2. [Déploiement courant](#2-déploiement-courant)
3. [Configurer Vault avec Ansible](#3-configurer-vault-avec-ansible)
4. [Résolution de problèmes](#4-résolution-de-problèmes)

---

## 1. Premier déploiement

### 1.1 Préparer l'accès SSH

Le provider Terraform `bpg/proxmox` a besoin d'un accès SSH root pour importer les disques.

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@<PROXMOX_HOST>
ssh-add ~/.ssh/id_ed25519
```

### 1.2 Configurer config.env

```bash
cp config.env.example config.env
```

Remplir toutes les valeurs :

```bash
PROXMOX_HOST="51.75.128.134"
PROXMOX_USER="root@pam"
PROXMOX_PASSWORD="..."
PROXMOX_NODE="proxmox-site1"
PROXMOX_STORAGE_VM="local"

VM_ID_UBUNTU_TEMPLATE=9000
VM_ID_PFSENSE_TEMPLATE=9001
VM_ID_PFSENSE=1001
VM_ID_SERVICES=1003
VM_ID_VAULT=1002
```

Pour connaître le nom du nœud Proxmox :

```bash
curl -s -k -X POST "https://<IP>:8006/api2/json/access/ticket" \
  --data-urlencode "username=root@pam" \
  --data-urlencode "password=<PASSWORD>" | python3 -c \
  "import sys,json; t=json.load(sys.stdin)['data']['ticket']; print(t)" > /tmp/ticket
curl -s -k -b "PVEAuthCookie=$(cat /tmp/ticket)" \
  "https://<IP>:8006/api2/json/nodes" | python3 -m json.tool
```

Pour connaître les storages disponibles :

```bash
ssh root@<PROXMOX_HOST> pvesm status
```

Utiliser un storage de type `dir` (ex: `local`) pour `PROXMOX_STORAGE_VM` afin que le cloud-init fonctionne.

### 1.3 Configurer terraform.tfvars

```bash
cp terraform/envs/onprem/terraform.tfvars.example terraform/envs/onprem/terraform.tfvars
```

Remplir les valeurs spécifiques à l'environnement (IPs des VMs, clé SSH publique) :

```hcl
vm_ip_cidr        = "172.16.255.242/28"
vm_gateway        = "172.16.255.254"
vault_vm_ip_cidr  = "172.16.255.243/28"
vm_ssh_public_key = "ssh-ed25519 AAAA..."   # cat ~/.ssh/id_ed25519.pub
```

### 1.4 Déployer

```bash
npm run deploy
```

Durée approximative : **10-15 minutes** (dont ~5 min pour le build Packer pfSense).

---

## 2. Déploiement courant

```bash
ssh-add ~/.ssh/id_ed25519   # si nouvelle session terminal
npm run deploy
```

Le script :
1. S'authentifie sur l'API Proxmox
2. Supprime les VMs existantes (pfSense, services, vault) — **pas les templates**
3. Vérifie/crée le bridge `vmbr1` (LAN pfSense)
4. Vérifie si le template pfSense (9001) existe — le rebuilde avec Packer si absent
5. Lance `terraform apply` avec toutes les valeurs de `config.env`

Pour tout supprimer :

```bash
npm run destroy
```

---

## 3. Configurer Vault avec Ansible

Une fois les VMs démarrées (attendre ~2 min après deploy) :

```bash
cd ansible
ansible-playbook playbooks/vault.yml -i inventory/onprem.yml
```

Le playbook installe Vault, configure le stockage Raft, init et unseal automatiquement.
Les unseal keys sont sauvegardées dans `/root/vault-init.json` sur la vault-vm.

Vérifier que Vault est opérationnel :

```bash
ssh ubuntu@172.16.255.243
export VAULT_ADDR='http://127.0.0.1:8200'
vault status
```

---

## 4. Résolution de problèmes

### Le script s'arrête silencieusement après "Authentification Proxmox..."

`curl` échoue avec `set -euo pipefail` et tue le script sans message.

Causes possibles :
- Proxmox inaccessible : `ping $PROXMOX_HOST`
- Mauvais mot de passe : vérifier `PROXMOX_PASSWORD` dans `config.env`
- Mauvaise IP : vérifier `PROXMOX_HOST` dans `config.env`

Test manuel :
```bash
source config.env
curl -k -X POST "https://${PROXMOX_HOST}:8006/api2/json/access/ticket" \
  --data-urlencode "username=${PROXMOX_USER}" \
  --data-urlencode "password=${PROXMOX_PASSWORD}"
```

---

### Packer — KVM virtualisation not available

```
Error starting VM: KVM virtualisation configured, but not available.
```

Proxmox tourne dans une VM VMware sans virtualisation imbriquée activée.

Fix appliqué : `disable_kvm = true` dans `packer/pfsense-2.7/pfsense-2.7.pkr.hcl`.
Le build est plus lent (~15 min) mais fonctionne.

Fix permanent : activer "Virtualize Intel VT-x/EPT" dans les settings processeur de la VM VMware, puis retirer `disable_kvm`.

---

### Packer — bridge 'vmbr1' does not exist

```
Error starting VM: bridge 'vmbr1' does not exist
```

Le bridge LAN n'existe pas encore sur Proxmox.

Le script `deploy.sh` le crée automatiquement via l'API avant le build Packer. Si le problème persiste, vérifier que l'appel API de création de bridge a réussi.

---

### Packer — hostname lookup 'proxmox-site1' failed

```
500 hostname lookup 'proxmox-site1' failed
```

Proxmox ne peut pas résoudre son propre hostname. L'erreur vient du serveur lui-même pendant l'upload de l'ISO.

Fix : ajouter le hostname dans `/etc/hosts` sur le serveur Proxmox.

```bash
ssh root@$PROXMOX_HOST \
  "grep -q proxmox-site1 /etc/hosts || echo '127.0.1.1 proxmox-site1' >> /etc/hosts"
```

---

### Packer — storage 'local-lvm' does not exist

```
500 storage 'local-lvm' does not exist
```

Le storage configuré dans `PROXMOX_STORAGE_VM` n'existe pas sur ce Proxmox.

Lister les storages disponibles :
```bash
ssh root@$PROXMOX_HOST pvesm status
```

Mettre à jour `PROXMOX_STORAGE_VM` dans `config.env` avec le bon nom.

---

### Terraform — storage 'local-lvm' does not exist (cloud-init)

```
Error: storage 'local-lvm' does not exist
  with module.services_vm / module.vault_vm
```

Le `initialization.datastore_id` dans les modules services-vm et vault-vm pointait sur `local-lvm` (stockage bloc) au lieu de `local` (stockage fichier). Le cloud-init a besoin d'un storage de type `dir`.

Fix appliqué : `storage_iso` passé aux modules et utilisé dans `initialization.datastore_id`.

---

### Terraform — No value for required variable

```
Error: No value for required variable
  variable "pfsense_vm_id"
```

Une variable sans `default` n'est pas passée via `-var` dans le `terraform apply` de `deploy.sh`.

Vérifier que toutes les variables de `config.env` ont bien un `-var` correspondant dans `deploy.sh` :

```bash
grep "var \"" scripts/deploy.sh
```

---

### VMs Ubuntu — temporary failure resolving / Cloud-init Final Stage

```
Temporary failure resolving 'archive.ubuntu.com'
Failed to start Cloud-init: Final Stage
```

Les VMs sont connectées à `vmbr0` (WAN) au lieu de `vmbr1` (LAN pfSense).
La gateway `172.16.255.254` est sur pfSense LAN (vmbr1), donc inaccessible depuis vmbr0.

Fix appliqué : `bridge = "vmbr1"` dans `services-vm/main.tf` et `vault-vm/main.tf`.

Ces erreurs sont aussi normales si pfSense n'est pas encore démarré — cloud-init échoue mais la VM reste fonctionnelle.

---

### State lock bloqué

```
Error: Error acquiring the state lock
```

```bash
ps aux | grep terraform     # vérifier si un process tourne encore
kill <PID>
rm terraform/envs/onprem/terraform.tfstate.lock.info
```

---

### VMs en statut io-error dans Proxmox

Le pool de stockage est plein.

```bash
ssh root@$PROXMOX_HOST pvesm status
```

Supprimer les VMs bloquées via `npm run destroy`, libérer de l'espace, puis re-déployer.

---

### Terraform reste bloqué sur "Still creating"

La VM boote. Cloud-init peut prendre 2-3 minutes. Terraform attend que le QEMU agent réponde.
Suivre la progression dans la console Proxmox (VM → Console).

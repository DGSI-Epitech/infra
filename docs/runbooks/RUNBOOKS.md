# Runbooks

Procédures pas à pas pour déployer et maintenir l'infrastructure.

---

## Sommaire

1. [Bootstrap Proxmox (première fois)](#1-bootstrap-proxmox-première-fois)
2. [Déployer les VMs avec Terraform](#2-déployer-les-vms-avec-terraform)
3. [Configurer Vault avec Ansible](#3-configurer-vault-avec-ansible)
4. [Résolution des problèmes fréquents](#4-résolution-des-problèmes-fréquents)

---

## 1. Bootstrap Proxmox (première fois)

Ces étapes ne sont à faire qu'une seule fois sur un Proxmox vierge. Tout est géré par Terraform — aucune action manuelle dans l'UI Proxmox.

### 1.1 Autoriser ta clé SSH sur Proxmox

Le provider Terraform `bpg/proxmox` a besoin d'un accès SSH root pour importer les disques des VMs. Il faut donc que ta clé publique soit autorisée.

**Sur ta machine locale :**

```bash
# Génère une clé SSH si tu n'en as pas encore
ssh-keygen -t ed25519 -C "ton@email.com"

# Copie ta clé publique sur le Proxmox (demande le mot de passe root Proxmox une fois)
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@<IP_PROXMOX>

# Vérifie que ça fonctionne (ne doit pas demander de mot de passe)
ssh root@<IP_PROXMOX> "echo connexion ok"

# Charge la clé dans l'agent SSH (à refaire à chaque session de terminal)
ssh-add ~/.ssh/id_ed25519
```

> **Pourquoi SSH en plus de l'API token ?**
> L'API Proxmox ne permet pas d'importer directement une image disque. Le provider Terraform se connecte en SSH pour exécuter les commandes `qm` nécessaires.

### 1.2 Lancer le bootstrap Terraform

Le bootstrap crée le rôle `TerraformRole`, génère le token `root@pam!terraform` et lui assigne les permissions nécessaires.

```bash
cd terraform/envs/bootstrap
cp terraform.tfvars.example terraform.tfvars
# Éditer terraform.tfvars : remplir proxmox_endpoint et proxmox_node_address

# Passer le mot de passe root via variable d'env (jamais dans un fichier)
export TF_VAR_proxmox_password='ton-mot-de-passe-root'

terraform init
terraform apply

# Afficher le token généré — à copier pour l'étape suivante
terraform output -raw terraform_token_id
```

> **Note** : si le token `root@pam!terraform` existe déjà sur Proxmox, le supprimer d'abord via l'UI (Datacenter → Permissions → API Tokens) avant de lancer le bootstrap.

### 1.3 Vérifier l'espace disque disponible

Le pool LVM de Proxmox doit avoir suffisamment d'espace. Connecte-toi en SSH et vérifie :

```bash
ssh root@<IP_PROXMOX>
pvesm status
```

La ligne `local-lvm` doit avoir de l'espace disponible (`Available > 0`). Si elle est à 100%, les VMs ne pourront pas démarrer (io-error).

Budget disque minimal pour ce projet :
- Template Ubuntu : ~20 GB thin (utilisation réelle ~1.6 GB)
- services-vm : 20 GB thin (utilisation réelle ~1-2 GB au démarrage)
- vault-vm : 20 GB thin (utilisation réelle ~1-2 GB au démarrage)

---

## 2. Déployer les VMs avec Terraform

### 2.1 Configurer les variables

```bash
cp terraform/envs/onprem/terraform.tfvars.example terraform/envs/onprem/terraform.tfvars
```

Édite `terraform.tfvars` avec tes valeurs. Exemple pour PVE1 :

```hcl
proxmox_endpoint     = "https://192.168.139.128:8006"
proxmox_node         = "pve"
proxmox_node_address = "192.168.139.128"
template_vm_id       = 9000

# services-vm (Netbox + website)
vm_ip_cidr           = "172.16.255.242/28"
vm_gateway           = "172.16.255.254"
vm_ssh_public_key    = "ssh-ed25519 AAAA..."  # cat ~/.ssh/id_ed25519.pub

# vault-vm (Elastic + Vault)
vault_vm_id          = 201
vault_vm_ip_cidr     = "172.16.255.243/28"
```

Récupère ta clé publique avec :
```bash
cat ~/.ssh/id_ed25519.pub
```

### 2.2 Injecter le token Proxmox

Le token ne doit jamais être écrit dans un fichier. Il se passe via variable d'environnement.

> **Important** : utilise des guillemets **simples** `'` — le `!` dans le token serait interprété par bash avec des guillemets doubles.

```bash
export TF_VAR_proxmox_api_token='root@pam!terraform=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
```

### 2.3 Lancer le déploiement

```bash
cd terraform/envs/onprem

# Initialise les plugins Terraform (à faire une fois ou après ajout de module)
terraform init

# Voir ce qui va être créé/modifié sans rien appliquer
terraform plan

# Déployer
terraform apply
```

Ce que Terraform va faire dans l'ordre :
1. Télécharger l'image Ubuntu 22.04 cloud depuis Canonical (~660 MB, une seule fois)
2. Créer la VM template (ID 9000) avec cette image
3. Cloner la template → créer services-vm (ID 200) et vault-vm (ID 201)
4. Configurer chaque VM via cloud-init : IP statique, hostname, clé SSH

La durée totale est d'environ **3-5 minutes**.

### 2.4 Vérifier le déploiement

Dans l'interface Proxmox, les VMs 200 et 201 doivent apparaître en statut **running**.

Teste la connexion SSH :
```bash
ssh ubuntu@172.16.255.242   # services-vm
ssh ubuntu@172.16.255.243   # vault-vm
```

> **Note** : si le réseau pfSense n'est pas encore configuré, les VMs seront accessibles uniquement depuis le réseau local Proxmox, pas depuis internet.

---

## 3. Configurer Vault avec Ansible

Une fois les VMs démarrées, Ansible installe et initialise HashiCorp Vault automatiquement.

```bash
cd ansible
ansible-playbook playbooks/vault.yml -i inventory/onprem.yml
```

Ce que fait le playbook :
1. Installe Vault via le dépôt officiel HashiCorp
2. Configure Vault (stockage Raft, écoute sur le port 8200)
3. Démarre et active le service `vault`
4. Exécute `vault operator init` si Vault n'est pas encore initialisé
5. Exécute `vault operator unseal` avec les 3 premières clés
6. Sauvegarde les unseal keys + root token dans `/root/vault-init.json` sur la VM

> **Sécurité** : `/root/vault-init.json` contient les clés maîtres de Vault. En production, ces clés doivent être stockées dans un coffre-fort sécurisé (HSM, secrets manager). En lab, garde ce fichier hors du dépôt git.

Vérifier que Vault est opérationnel :
```bash
ssh ubuntu@172.16.255.243
export VAULT_ADDR='http://127.0.0.1:8200'
vault status
```

---

## 4. Résolution des problèmes fréquents

### State lock bloqué

```
Error: Error acquiring the state lock
```

Un process Terraform précédent a été interrompu. Vérifie s'il tourne encore :
```bash
ps aux | grep terraform
kill <PID>
```

Si aucun process ne tourne, supprime le fichier de lock :
```bash
rm terraform/envs/onprem/terraform.tfstate.lock.info
```

---

### Erreur de format de token

```
the API token must be in the format 'USER@REALM!TOKENID=UUID'
```

Le token n'est pas défini ou mal formaté. Exporte-le avec des guillemets simples :
```bash
export TF_VAR_proxmox_api_token='root@pam!terraform=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
```

---

### Erreur SSH / authentification

```
unable to authenticate user "root" over SSH
```

La clé SSH n'est pas chargée ou pas autorisée sur Proxmox :
```bash
ssh-add ~/.ssh/id_ed25519           # charge la clé dans l'agent
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@<IP_PROXMOX>   # autorise la clé
```

---

### Erreur de format IP (gateway invalide)

```
ipconfig0.gw: invalid format - value does not look like a valid IPv4 address
```

La variable `vm_gateway` dans `terraform.tfvars` contient encore la valeur placeholder `<GATEWAY_IP>`. Remplace-la par la vraie IP :
```hcl
vm_gateway = "172.16.255.254"
```

---

### VMs en statut io-error dans Proxmox

Le pool LVM-thin est plein. Vérifie :
```bash
ssh root@<IP_PROXMOX>
pvesm status
```

Si `local-lvm` est à 100%, supprime les VMs en erreur pour libérer de l'espace :
```bash
qm stop 200 --skiplock; qm destroy 200 --destroy-unreferenced-disks 1
qm stop 201 --skiplock; qm destroy 201 --destroy-unreferenced-disks 1
```

Puis relance `terraform apply`.

---

### Erreur de réduction de disque

```
disk resize failure: requested size (8G) is lower than current size (20G)
```

Proxmox ne peut pas réduire un disque existant. Les disques des VMs clonées héritent de la taille de la template (20 GB). Il ne faut pas définir une taille inférieure dans les modules clone.

---

### cloud-init : échec DNS / pas d'internet

```
Temporary failure resolving 'security.ubuntu.com'
```

C'est normal si pfSense n'est pas encore déployé — il n'y a pas de gateway pour sortir sur internet. Cloud-init continue quand même, la VM reste fonctionnelle sur le réseau local.

---

### Terraform reste bloqué sur "Still creating"

La VM est en train de booter. Cloud-init peut prendre 2-3 minutes. Pendant ce temps, Terraform attend que le QEMU agent réponde. Tu peux suivre la progression dans :
- L'interface Proxmox → VM → Console (affiche les logs cloud-init en temps réel)
- Tasks du nœud Proxmox (affiche les tâches de clonage/création)

---

## Adressage réseau

### PVE1 — On-premise (Site 1)

| Élément | Valeur |
|---|---|
| Proxmox URL | `https://ns3050272.ip-51-255-76.eu:8006` |
| Proxmox IP local | `192.168.139.128` |
| pfSense domaine | `op.local` |
| WAN | `5.196.45.8` |
| LAN réseau | `172.16.255.240/28` |
| LAN gateway | `172.16.255.254` |
| LAN plage utilisable | `172.16.255.241` → `172.16.255.253` (13 adresses) |

| VM | IP | Rôle |
|---|---|---|
| services-vm (ID 200) | `172.16.255.242` | Netbox, website |
| vault-vm (ID 201) | `172.16.255.243` | HashiCorp Vault, Elastic |
| Template Ubuntu (ID 9001) | — | Base pour les clones |

### PVE2 — Cloud (Site 2)

| Élément | Valeur |
|---|---|
| Proxmox URL | `https://ns3183326.ip-146-59-253.eu:8006` |
| pfSense domaine | `cloud.local` |
| WAN | `5.196.50.52` |
| DMZ réseau | `10.255.255.248/29` (5 adresses) |
| DMZ gateway | `10.255.255.254` |
| LAN réseau | `192.168.255.240/28` |
| LAN gateway | `192.168.255.254` |

| VM | IP | Rôle |
|---|---|---|
| Teleport | `10.255.255.249` | Bastion SSH |
| website | `192.168.255.243` | Site web |

---

## 5. Reconstruire le template pfSense

Si le template pfSense doit être reconstruit (changement de config réseau, mise à jour) :

```bash
# 1. Rebuild le template avec Packer
cd packer/pfsense-2.7/
packer build -force -var-file="pfsense-2.7.pkrvars.hcl" .

# 2. Redéployer uniquement le module pfSense
cd terraform/envs/onprem/
terraform destroy -target=module.pfsense
terraform apply -target=module.pfsense
```
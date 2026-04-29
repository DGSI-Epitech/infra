# Authentification SSH — Architecture et flux

Ce document décrit comment l'authentification SSH fonctionne dans l'infrastructure, depuis le bootstrap Packer jusqu'aux connexions Ansible en production.

---

## Vue d'ensemble

Une seule paire de clés SSH (`~/.ssh/id_ed25519`) est utilisée pour toutes les connexions machine-à-machine. Zéro password dans le repo. Les secrets applicatifs post-bootstrap sont gérés par HashiCorp Vault.

```
Opérateur
  │
  ├─ clé privée ~/.ssh/id_ed25519
  │
  ├──► Proxmox (root)          via SSH directe
  ├──► pfSense (admin)         via SSH, clé injectée dans config.xml au build Packer
  ├──► vault-vm (ubuntu)       via SSH, clé injectée par cloud-init Terraform
  └──► services-vm (ubuntu)    via SSH, clé injectée par cloud-init Terraform
```

---

## Flux par composant

### 1. Packer pfSense

**Problème :** pfSense n'a pas de cloud-init. La configuration doit être injectée pendant l'installation.

**Solution :** Le fichier `config.xml.pkrtpl.hcl` est un template Packer. La clé publique SSH (`SSH_PUBLIC_KEY` depuis `config.env`) est encodée en base64 et injectée dans le champ `<authorizedkeys>` du compte `admin` pfSense.

```
config.env (SSH_PUBLIC_KEY)
  └─► deploy.sh (PKR_VAR_pfsense_admin_ssh_public_key)
        └─► pfsense-2.7.pkr.hcl (base64encode → templatefile)
              └─► config.xml.pkrtpl.hcl (<authorizedkeys>BASE64</authorizedkeys>)
                    └─► pfSense template Proxmox
```

Ansible se connecte ensuite à pfSense avec `ansible_ssh_private_key_file: ~/.ssh/id_ed25519`.

### 2. Packer Ubuntu

**Problème :** Packer doit SSH dans la VM *pendant le build* pour exécuter les provisioners. Mais la VM est sur `vmbr1` (réseau privé), inaccessible directement.

**Solution :**
1. La clé publique SSH est injectée dans le `user-data` autoinstall via le champ `ssh.authorized-keys`.
2. Packer utilise `ssh_private_key_file` (clé privée locale) pour se connecter.
3. Proxmox est utilisé comme bastion SSH (`ssh_bastion_private_key_file`) — Proxmox accepte la connexion car la clé est déjà présente via `ssh-copy-id`.
4. À la fin du build, le dernier provisioner **supprime `/home/ubuntu/.ssh`** et verrouille le compte (`passwd -l ubuntu`). Le template est ainsi "vierge" de tout credential.

```
Packer (local)
  │  ssh_private_key_file = ~/.ssh/id_ed25519
  │
  └──► Proxmox bastion (ssh_bastion_private_key_file = ~/.ssh/id_ed25519)
         └──► VM Ubuntu (172.16.0.100, vmbr1)
                └─► provisioners s'exécutent
                └─► BLOC 3 : rm -rf /home/ubuntu/.ssh && passwd -l ubuntu
```

### 3. Terraform cloud-init (clones Ubuntu)

**Problème :** cloud-init n'injecte pas les clés SSH dans un user créé par autoinstall Packer si `.ssh/authorized_keys` existe déjà.

**Fix (lié au Bloc 3 Packer) :** Puisque le template est livré sans `/home/ubuntu/.ssh`, cloud-init sur le clone trouve un répertoire absent et peut créer `authorized_keys` correctement.

```
Terraform (user_account.keys = SSH_PUBLIC_KEY)
  └─► cloud-init au boot du clone
        └─► /home/ubuntu/.ssh/authorized_keys créé proprement
```

Résultat : `vault-vm` et `services-vm` n'ont aucun password — connexion SSH key-only uniquement.

### 4. Terraform provider bpg/proxmox — SSH pour import disque

Le provider `bpg/proxmox` a besoin d'un accès SSH root à Proxmox pour importer les disques cloud-image. Il utilise `private_key = file(pathexpand(var.proxmox_ssh_private_key))` au lieu d'un password.

---

## Ce qui vient après (Phase 2 — Vault opérationnel)

Une fois Vault déployé sur `vault-vm`, il prend la relève pour les secrets dynamiques :

| Usage | Mécanisme Vault |
|---|---|
| Certificats OpenVPN inter-sites | PKI secrets engine |
| Clés SSH éphémères pour accès VMs | SSH secrets engine (signed certificates) |
| Secrets applicatifs (Netbox, website) | KV v2 secrets engine |
| Auth Terraform vers Vault | AppRole auth method |

Les secrets injectés au bootstrap (dans `config.env`) ne couvrent que Phase 0 (avant que Vault existe). Tout ce qui vient après est géré dynamiquement.

---

## Prérequis opérateur

```bash
# 1. Générer une paire de clés si elle n'existe pas
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "lab-infra"

# 2. Copier la clé publique sur Proxmox
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@<PROXMOX_HOST>

# 3. Remplir config.env
SSH_PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)"
SSH_PRIVATE_KEY_FILE="~/.ssh/id_ed25519"
```

---

## Sécurité — Ce qui reste en clair

| Secret | Où | Justification |
|---|---|---|
| `PROXMOX_PASSWORD` | `config.env` (gitignore) | Nécessaire pour l'auth API Proxmox (ticket curl) — remplaçable par token API à terme |
| Bcrypt-hash admin pfSense | `config.xml.pkrtpl.hcl` | Hash du mot de passe web UI pfSense — ne donne pas d'accès SSH |
| Clé publique SSH | Partout (config.env, config.xml) | Une clé publique n'est pas un secret |

Le `PROXMOX_PASSWORD` est le seul secret restant "sensible". Il est dans `config.env` qui est gitignore. La prochaine étape est de le remplacer par un token API Proxmox (`PROXMOX_TOKEN`) qui peut avoir des permissions réduites.

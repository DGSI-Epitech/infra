# Authentification SSH — Architecture et flux

Une seule paire de clés SSH (`~/.ssh/id_ed25519`) pour tous les accès machine. Zéro password dans le repo. Les secrets applicatifs post-bootstrap sont gérés par HashiCorp Vault.

---

## Vue d'ensemble

```
Opérateur (machine locale)
  │  ~/.ssh/id_ed25519
  │
  ├──► Proxmox root (51.75.128.134)     SSH directe
  │         │
  │         │  ProxyJump
  │         ├──► vault-vm    (172.16.0.x)   clé injectée via QEMU agent
  │         └──► services-vm (172.16.0.x)   clé injectée via QEMU agent
  │
  ├──► pfSense admin (172.16.0.254)     clé dans config.xml (Packer)
  │
  └──► VM Ubuntu pendant build Packer   password éphémère (jamais stocké)
```

Les VMs Ubuntu (`vault-vm`, `services-vm`) sont sur `vmbr1`, un réseau privé inaccessible directement depuis l'extérieur. Tout accès passe par Proxmox comme **ProxyJump SSH**.

---

## Flux par composant

### 1. Packer pfSense — clé dans config.xml

pfSense n'a pas de cloud-init. La configuration est injectée à l'installation via un CD contenant `config.xml`.

La clé publique SSH (`SSH_PUBLIC_KEY` de `config.env`) est encodée en base64 et placée dans `<authorizedkeys>` du compte `admin` pfSense lors du build Packer.

```
config.env (SSH_PUBLIC_KEY)
  └─► deploy.sh (PKR_VAR_pfsense_admin_ssh_public_key)
        └─► pfsense-2.7.pkr.hcl
              └─► templatefile(config.xml.pkrtpl.hcl)
                    └─► <authorizedkeys>BASE64</authorizedkeys>
                          └─► template Proxmox ID 2000
```

### 2. Packer Ubuntu — password éphémère + ProxyJump

**Problème :** La VM Ubuntu est sur `vmbr1` (réseau privé). Packer doit s'y connecter pendant le build pour exécuter les provisioners.

**Solution choisie :** Password éphémère généré à la volée dans `deploy.sh`, jamais écrit nulle part.

```bash
# Dans deploy.sh — généré à chaque build, disparu dès la fin du script
_PACKER_PASS="$(openssl rand -base64 16 | tr -d '+/=' | head -c 20)"
export PKR_VAR_build_password="${_PACKER_PASS}"
export PKR_VAR_build_password_hash="$(echo "${_PACKER_PASS}" | openssl passwd -6 -stdin)"
unset _PACKER_PASS
```

**Pourquoi pas une clé SSH directement ?**
La clé SSH dans `ssh.authorized-keys` de l'autoinstall Ubuntu n'est pas fiable : race condition entre le montage des filesystems au reboot et la tentative de connexion de Packer. Le password est déterministe et disponible dès que SSH démarre.

**Flux complet :**
```
deploy.sh génère RANDOM_PASS + HASH
  │
  ├─► user-data.pkrtpl.hcl : identity.password = HASH → user créé avec ce mot de passe
  │
  └─► Packer communicator : ssh_password = RANDOM_PASS
        │  ssh_bastion_host = PROXMOX_HOST (ProxyJump)
        │  ssh_bastion_private_key_file = ~/.ssh/id_ed25519
        │
        └─► VM Ubuntu (172.16.0.100, vmbr1)
              ├─► BLOC 1 : apt upgrade + reboot
              ├─► BLOC 2 : install tools + cloud-init clean
              ├─► BLOC 3 : echo SSH_PUBLIC_KEY > ~/.ssh/authorized_keys
              │            sed PasswordAuthentication no
              └─► BLOC 4 : rm -rf ~/.ssh + passwd -l ubuntu
                           → template propre, aucun credential résiduel
```

### 3. Terraform cloud-init — clé NON injectée, QEMU agent utilisé à la place

**Problème connu :** `bpg/proxmox` provider passe la clé SSH via `user_account.keys`, qui se traduit en cloud-init `user_account`. Mais cloud-init ignore l'injection de clé SSH pour un user créé par autoinstall Ubuntu (subiquity) car il considère le user comme "déjà existant".

**Conséquence :** `vm_password` a été retiré (plus de password), la clé cloud-init est configurée mais non appliquée.

**Fix — injection via QEMU agent :**

Après le `terraform apply`, `deploy.sh` utilise l'API Proxmox pour exécuter une commande dans chaque VM via le QEMU guest agent :

```bash
# API Proxmox : POST /nodes/{node}/qemu/{vmid}/agent/exec
{"command":["bash","-c","mkdir -p /home/ubuntu/.ssh && echo 'SSH_KEY' > ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys && chown -R ubuntu:ubuntu ~/.ssh"]}
```

Sequence dans deploy.sh :
```
terraform apply (VMs créées)
  └─► wait_for_agent(vault-vm)    # QEMU agent opérationnel ?
  └─► wait_for_agent(services-vm)
  └─► inject_ssh_key(vault-vm)    # écriture authorized_keys via API
  └─► inject_ssh_key(services-vm)
  └─► wait_for_ssh(vault-vm)      # vérification SSH via ProxyJump
  └─► wait_for_ssh(services-vm)
  └─► ansible-playbook
```

### 4. Ansible — ProxyJump + inventaire dynamique

Les VMs étant sur `vmbr1`, inaccessibles directement, Ansible passe par Proxmox comme ProxyJump SSH.

L'inventaire est un **script Python dynamique** (`inventory/onprem.py`) qui lit `config.env` à la racine du repo. Les IPs, la clé SSH et le ProxyJump sont toujours cohérents avec la configuration courante.

```python
# onprem.py génère dynamiquement :
"ansible_ssh_common_args": "-o StrictHostKeyChecking=no -o ProxyJump=root@{proxmox_host}"
```

Pour les runs manuels :
```bash
ansible-playbook playbooks/vault.yml -i inventory/onprem.py
```

### 5. Terraform provider bpg/proxmox — SSH pour import disque

Le provider `bpg/proxmox` a besoin d'un accès SSH root à Proxmox pour importer les disques cloud-image (pas de password, clé privée) :

```hcl
ssh {
  username    = "root"
  private_key = file(pathexpand(var.proxmox_ssh_private_key))
}
```

---

## Séquence complète d'un déploiement

```
npm run deploy
  │
  ├─[1] Auth API Proxmox (PROXMOX_PASSWORD → ticket temporaire)
  ├─[2] Nettoyage VMs existantes
  ├─[3] Vérification/création bridge vmbr1
  │
  ├─[4] Packer pfSense (si template absent)
  │       └─► clé SSH dans config.xml → template ID 2000
  │
  ├─[5] Terraform pfSense → clone template → pfsense-fw-01 démarré
  │       └─► attente 30s
  │
  ├─[6] Packer Ubuntu (si template absent)
  │       └─► password éphémère → build → clé injectée → nettoyée → template ID 1000
  │
  ├─[7] Terraform vault-vm + services-vm → clones + cloud-init IP
  │
  ├─[8] wait_for_agent + inject_ssh_key (QEMU agent API)
  │
  ├─[9] wait_for_ssh (ProxyJump via Proxmox)
  │
  └─[10] Ansible → installe Vault, configure Raft, init + unseal
```

---

## Sécurité — Ce qui reste en clair

| Secret | Où | Justification |
|---|---|---|
| `PROXMOX_PASSWORD` | `config.env` (gitignore) | Auth API Proxmox — remplaçable par token API à terme |
| Bcrypt-hash admin pfSense | `config.xml.pkrtpl.hcl` | Hash du password web UI pfSense, pas d'accès SSH |
| Clé publique SSH | `config.env`, `config.xml` | Une clé publique n'est pas un secret |
| Password éphémère Packer | Mémoire RAM uniquement | Généré + détruit dans le même processus shell |

---

## Phase 2 — Vault remplace config.env

Une fois Vault opérationnel sur `vault-vm`, il prend la relève :

| Usage | Mécanisme Vault |
|---|---|
| Certificats OpenVPN inter-sites | PKI secrets engine |
| Accès SSH aux VMs | SSH secrets engine (certificats signés éphémères) |
| Secrets applicatifs | KV v2 secrets engine |
| Auth Terraform/Ansible → Vault | AppRole auth method |

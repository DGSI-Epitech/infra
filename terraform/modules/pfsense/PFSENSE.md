# pfSense — Configuration Ansible

Ce document couvre la configuration automatisée des deux pfSense via Ansible (`playbooks/pfsense.yml`).

Pour la création des templates Packer, voir `docs/architecture/pfsense.md`.

---

## Prérequis

### 1. Installer la collection Ansible pfsensible

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
```

`requirements.yml` contient :
```yaml
collections:
  - name: pfsensible.core
    version: "0.7.1"
```

> La version 0.7.2 n'existe pas sur Galaxy — utiliser 0.7.1.

### 2. Vérifier config.env

Les variables suivantes doivent être renseignées dans `config.env` :

| Variable | Valeur | Description |
|---|---|---|
| `PFSENSE_OP_WAN` | `5.196.45.8` | IP WAN routable pfSense OP |
| `PFSENSE_CLOUD_WAN` | `5.196.50.52` | IP WAN routable pfSense Cloud |
| `PFSENSE_PASSWORD` | `pfsense` | Mot de passe compte `admin` pfSense |
| `VM_GATEWAY` | `172.16.0.254` | Gateway LAN PVE1 (pfSense OP) |
| `VM_GATEWAY2` | `192.168.255.254` | Gateway LAN PVE2 (pfSense Cloud) |

---

## Lancer le playbook

```bash
cd ansible

# Configuration complète (firewall, VPN, DNS)
ansible-playbook -i inventory/onprem.py playbooks/pfsense.yml

# Couper le VPN en urgence (kill-switch)
ansible-playbook -i inventory/onprem.py playbooks/pfsense.yml --tags killswitch

# Rétablir le VPN après un kill-switch
ansible-playbook -i inventory/onprem.py playbooks/pfsense.yml --tags restore
```

Ansible se connecte directement sur les IPs WAN avec le compte `admin` en authentification par mot de passe.

> La clé OpenVPN partagée est dans `ansible/vars/openvpn_secrets.yml` (gitignored — ne pas committer).

---

## Ce que configure le playbook

### pfSense OP — Site on-premise (op.local)

| Tâche | Détail |
|---|---|
| Règle LAN → WAN | Autorise tout le trafic sortant depuis le LAN |
| Règle SSH WAN | Autorise SSH entrant sur le WAN (port 22) |
| Règle HTTPS WAN | Autorise HTTPS entrant sur le WAN (port 443) — accès webGUI |
| Règle OpenVPN 1194 | Autorise UDP 1194 sur WAN |
| Règle OpenVPN interface | Autorise tout le trafic inter-sites sur l'interface OpenVPN |
| Client OpenVPN | Connexion vers pfSense Cloud (`5.196.50.52:1194`) — tunnel `10.3.3.0/30` |
| DNS Forwarders | `192.168.255.254` (Cloud via VPN) + `1.1.1.1` + `8.8.8.8` |

### pfSense Cloud — Site cloud (cloud.local)

| Tâche | Détail |
|---|---|
| Règle DMZ → ANY | Autorise tout le trafic depuis la DMZ (`opt1`) |
| Règle LAN → ANY | Autorise tout le trafic depuis le LAN |
| Règle SSH WAN | Autorise SSH entrant sur le WAN (port 22) |
| Règle HTTPS WAN | Autorise HTTPS entrant sur le WAN (port 443) — accès webGUI |
| Règle OpenVPN 1194 | Autorise UDP 1194 entrant sur le WAN |
| Règle OpenVPN interface | Autorise tout le trafic inter-sites sur l'interface OpenVPN |
| Serveur OpenVPN | Écoute sur `1194/UDP` — tunnel `10.3.3.0/30`, route vers OP LAN `172.16.0.240/28` |
| DNS Forwarders | `172.16.0.254` (OP via VPN) + `8.8.8.8` (secours) |

---

## Architecture réseau configurée

```
Internet
    │
    ├── PVE1 (OP)  5.196.45.8
    │       └── pfSense S1 (op.local)
    │               ├── WAN  vmbr0
    │               └── LAN  vmbr1  172.16.0.240/28  GW 172.16.0.254
    │                           └── vault-vm  172.16.0.253
    │
    └── PVE2 (Cloud)  5.196.50.52
            └── pfSense S2 (cloud.local)
                    ├── WAN  vmbr0
                    ├── DMZ  vmbr134  10.255.255.248/29   GW 10.255.255.254
                    │           └── bastion  10.255.255.253
                    └── LAN  vmbr133  192.168.255.240/28  GW 192.168.255.254
                                └── web  192.168.255.253

Tunnel OpenVPN inter-sites : 10.3.3.0/30 (server=10.3.3.1, client=10.3.3.2)
DNS OP    → 192.168.255.254 (Cloud) via VPN → 1.1.1.1 → 8.8.8.8
DNS Cloud → 172.16.0.254 (OP) via VPN → 8.8.8.8
```

---

## Accès au webGUI pfSense

Le webGUI est accessible directement depuis un navigateur via les IPs WAN — la règle HTTPS WAN est configurée par le playbook.

| pfSense | URL | Login |
|---|---|---|
| OP (on-premise) | https://5.196.45.8 | `admin` / `PFSENSE_PASSWORD` (config.env) |
| Cloud | https://5.196.50.52 | `admin` / `PFSENSE_PASSWORD` (config.env) |

Accepter le certificat auto-signé lors de la première connexion.

### Vérifier les règles firewall via le GUI

1. Ouvrir l'URL ci-dessus dans le navigateur
2. Aller dans **Firewall > Rules > WAN** — les règles SSH (22), HTTPS (443) et OpenVPN (1194) doivent être présentes
3. Aller dans **Services > DNS Forwarder** ou **DNS Resolver** pour vérifier les forwarders

### Prérequis : SSH activé sur pfSense

Ansible se connecte via SSH. Si le playbook échoue avec `Connection timed out`, SSH est peut-être désactivé sur pfSense.

Pour le réactiver sans accès réseau :
1. Ouvrir la console Proxmox : `https://ns3050272.ip-51-255-76.eu:8006` (pour OP) ou `https://ns3183326.ip-146-59-253.eu:8006` (pour Cloud)
2. Sélectionner la VM pfSense → **Console**
3. Choisir l'**option 14** (Enable Secure Shell) — cette option toggle SSH, sélectionner une fois pour activer, une fois pour désactiver

---

## Emergency cut-off VPN (kill-switch)

Coupe le tunnel inter-sites immédiatement. Le SSH WAN reste accessible sur les deux pfSenses pour récupération.

```bash
cd ansible

# Couper le VPN
ansible-playbook -i inventory/onprem.py playbooks/pfsense.yml --tags killswitch

# Rétablir le VPN
ansible-playbook -i inventory/onprem.py playbooks/pfsense.yml --tags restore
```

**Ce que fait le kill-switch :**
1. Ajoute une règle `KILLSWITCH_OpenVPN_1194` (block UDP 1194) sur le WAN des deux pfSenses
2. Tue le processus OpenVPN actif — le tunnel tombe immédiatement

**Ce que fait le restore :**
1. Supprime la règle `KILLSWITCH_OpenVPN_1194`
2. Recrée le serveur/client OpenVPN — le tunnel remonte en ~20 secondes

---

## Résolution de problèmes

### Permission denied sur le WAN

pfsensible.core utilise l'authentification par **mot de passe** (pas clé SSH). Vérifier que `PFSENSE_PASSWORD` est correct dans `config.env`.

### Module pfsensible introuvable

```
couldn't resolve module/action 'pfsensible.core.pfsense_rule'
```

La collection n'est pas installée :
```bash
ansible-galaxy collection install -r requirements.yml
```


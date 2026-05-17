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
| `VM_GATEWAY` | `172.16.255.254` | Gateway LAN PVE1 (pfSense OP) |
| `VM_GATEWAY2` | `192.168.255.254` | Gateway LAN PVE2 (pfSense Cloud) |

---

## Lancer le playbook

```bash
cd ansible
ansible-playbook playbooks/pfsense.yml -i inventory/onprem.py
```

Ansible se connecte directement sur les IPs WAN (pas de ProxyJump) avec le compte `admin` en authentification par mot de passe.

---

## Ce que configure le playbook

### pfSense OP — Site on-premise (op.local)

| Tâche | Détail |
|---|---|
| Règle LAN → WAN | Autorise tout le trafic sortant depuis le LAN |
| Règle SSH WAN | Autorise SSH entrant sur le WAN (port 22) |
| Règle HTTPS WAN | Autorise HTTPS entrant sur le WAN (port 443) — accès webGUI |
| Règle OpenVPN | Autorise tout le trafic dans le tunnel OpenVPN |
| DNS Forwarders | `1.1.1.1` + `8.8.8.8` |
| DNS Resolver | Activé en mode Forwarder — écoute sur LAN, sort par WAN |
| CA interne | Crée `CAPfsense` (RSA 4096, SHA-256, 10 ans) si absente |
| Export CA | Sauvegarde `CAPfsense.crt` en local (uniquement à la création) |

### pfSense Cloud — Site cloud (cloud.local)

| Tâche | Détail |
|---|---|
| Règle DMZ → ANY | Autorise tout le trafic depuis la DMZ (`opt1`) |
| Règle LAN → ANY | Autorise tout le trafic depuis le LAN |
| Règle SSH WAN | Autorise SSH entrant sur le WAN (port 22) |
| Règle HTTPS WAN | Autorise HTTPS entrant sur le WAN (port 443) — accès webGUI |
| Règle OpenVPN 1194 | Autorise UDP 1194 entrant sur le WAN |
| Règle OpenVPN | Autorise tout le trafic dans le tunnel OpenVPN |
| DNS Forwarders | `172.16.255.254` (via VPN) + `8.8.8.8` (secours) |
| DNS Resolver | Activé en mode Forwarder — écoute sur LAN + DMZ (`opt1`), sort par WAN |

---

## Architecture réseau configurée

```
Internet
    │
    ├── PVE1 (OP)  5.196.45.8
    │       └── pfSense S1 (op.local)
    │               ├── WAN  vmbr0
    │               └── LAN  vmbr1  172.16.255.240/28  GW 172.16.255.254
    │                           └── vault-vm  172.16.255.253
    │
    └── PVE2 (Cloud)  5.196.50.52
            └── pfSense S2 (cloud.local)
                    ├── WAN  vmbr0
                    ├── DMZ  vmbr134  10.255.255.248/29   GW 10.255.255.254
                    │           └── bastion  10.255.255.253
                    └── LAN  vmbr133  192.168.255.240/28  GW 192.168.255.254
                                └── web  192.168.255.253

Tunnel OpenVPN inter-sites : 10.3.3.0/29
DNS OP  → 192.168.255.254 via VPN
DNS Cloud → 172.16.255.254 via VPN
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
4. Aller dans **System > Cert. Manager > CAs** pour vérifier la CA `CAPfsense`

### Prérequis : SSH activé sur pfSense

Ansible se connecte via SSH. Si le playbook échoue avec `Connection timed out`, SSH est peut-être désactivé sur pfSense.

Pour le réactiver sans accès réseau :
1. Ouvrir la console Proxmox : `https://ns3050272.ip-51-255-76.eu:8006` (pour OP) ou `https://ns3183326.ip-146-59-253.eu:8006` (pour Cloud)
2. Sélectionner la VM pfSense → **Console**
3. Choisir l'**option 14** (Enable Secure Shell) — cette option toggle SSH, sélectionner une fois pour activer, une fois pour désactiver

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

### CA skipped à la sauvegarde

La tâche "Sauvegarder le certificat public CA en local" est sautée si la CA existait déjà. C'est normal — `ca_result.ca` n'est renvoyé que lors de la création.

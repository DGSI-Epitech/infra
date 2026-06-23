# Decisions

---

## Teleport — Bastion SSH centralisé (PVE2 Cloud)

**Date :** 2026-06-01

### Contexte

Le bastion Cloud (`10.255.255.249`, vmbr3) centralise tous les accès SSH à l'infrastructure. Teleport remplace les ProxyJump manuels (`-J root@51.75.128.134`) par un bastion avec audit log, RBAC et interface web.

### Décisions

**Install via apt (pas Docker)**

Teleport a besoin d'accéder nativement au filesystem hôte pour l'audit SSH. Un container Docker nécessiterait de nombreux montages en lecture-only avec des permissions complexes. L'installation via le repo apt officiel (`stable/v16`) est plus simple et suit le pattern de elastic-agent.

**Auth + Proxy + SSH sur le même nœud (bastion)**

Pour un cluster de lab, les trois services Teleport tournent sur la même VM. Séparation possible ultérieurement si l'infra grandit (auth server dédié + N proxy servers).

**TLS via la PKI interne existante**

Le rôle `tls` génère des certs avec les SANs nécessaires (`IP:10.255.255.249`, `IP:51.75.128.134`, `DNS:teleport`, `DNS:bastion.cloud.local`). `IP:51.75.128.134` couvre la DNAT externe — les clients se connectent via `51.75.128.134:3080` mais le cert TLS répond `10.255.255.249`.

**Join token stocké dans Vault KV**

Même pattern que le Fleet enrollment token d'Elastic Agent. Le rôle `teleport` génère un token aléatoire au premier déploiement, le stocke dans `secret/data/teleport/join-token`. Le rôle `teleport-node` le lit depuis Vault pour enrôler les VMs on-prem (Phase 5).

**Port forwarding DNAT sur Proxmox hôte**

Le bastion est dans une DMZ privée (`10.255.255.248/29`). L'accès depuis internet passe par DNAT sur l'hôte Proxmox :
- `51.75.128.134:3080` → `10.255.255.249:443` (Teleport Web UI)
- `51.75.128.134:3022` → `10.255.255.249:3022` (Teleport SSH proxy)

Règles persistées dans `/etc/network/interfaces` (`post-up`/`post-down` sur `vmbr3`).

**Port auth 3025 restreint aux réseaux internes**

UFW autorise 3025 uniquement depuis `10.255.255.248/29` (Cloud DMZ) et `172.16.0.0/24` (LAN on-prem). Ce port n'est jamais exposé à internet.

### Scalabilité — rôle `teleport-node`

Le rôle `teleport-node` permet d'enrôler n'importe quelle VM dans le cluster sans modifier son SSH :
```yaml
roles:
  - teleport-node  # ajouter à n'importe quel playbook
```

Pour les VMs PVE1 (ops-vm, services-vm), le trafic vers `10.255.255.249:3025` transite via l'hôte Proxmox (qui route entre vmbr1 et vmbr3). Une route statique sur pfSense on-prem sera nécessaire.

---

## fail2ban sur le bastion — durcissement port 22

**Date :** 2026-06-23

### Contexte

Le bastion est le seul host exposé sur internet. Le rôle `base` ouvre le port 22 sur tous les hosts (y compris bastion) sans protection anti-bruteforce — c'est le premier trou évident à combler avant d'aller plus loin sur le durcissement.

### Décisions

**Nouveau rôle dédié (`fail2ban`) plutôt qu'ajout direct dans `base` ou `teleport`**

`base` est partagé par tous les hosts (ops, services, bastion, web) — fail2ban n'est utile que sur un host exposé à internet, pas sur les VMs internes. L'ajouter dans `teleport.yml` (`roles: base, tls, teleport, fail2ban`) garde le scope correct sans polluer `base`.

**`banaction = ufw` plutôt que l'action iptables par défaut de fail2ban**

Tout le firewall du repo passe par `community.general.ufw` (`base`, `teleport`). L'action par défaut de fail2ban crée ses propres chaînes iptables (`f2b-sshd`), ce qui peut entrer en conflit d'ordonnancement avec les chaînes gérées par UFW. Configurer `banaction = ufw` fait passer les bans par `ufw insert ... deny`, dans le même système que le reste de l'infra.

**Scope limité au jail `sshd` (port 22) — port 3022 (Teleport SSH proxy) volontairement exclu**

Le jail `sshd` standard parse les logs d'échec d'auth OpenSSH (`backend = systemd`, journald sur Ubuntu 22.04) — il protège le port 22 utilisé par Ansible. Le port 3022 est le proxy SSH de Teleport : protocole et logs d'audit propres à Teleport, pas de lignes `auth.log` exploitables par le filtre `sshd`. Protéger ce port demanderait soit un filtre fail2ban custom sur les events d'audit Teleport, soit (plus naturel) la fonctionnalité native `connection_limits` de Teleport — non traité dans cette passe.

### Vérification

```bash
ansible bastion -i inventory/onprem.py -m shell -a "fail2ban-client status sshd" --become
```

---

## SSH (22) restreint au VPN site-to-site sur le bastion

**Date :** 2026-06-23

### Contexte

fail2ban protège contre le bruteforce mais n'empêche pas une connexion SSH directe depuis n'importe quelle IP — le port 22 reste ouvert au monde via la règle générique du rôle `base`. Le bastion ne doit accepter SSH que depuis les réseaux reliés par le tunnel OpenVPN site-to-site (pfSense OP ↔ pfSense Cloud), pas depuis internet en direct.

### Décisions

**Suppression de la règle UFW générique de `base`, remplacée par deux règles scoping dans `teleport`**

`base` ouvre `22/tcp` sans `src` sur tous les hosts — correct pour les VMs internes (ops, services, web), pas pour le bastion qui est le seul host avec une façade internet. Le rôle `teleport` (qui gère déjà le scoping CIDR du port 3025) supprime cette règle (`delete: true`) et la remplace par deux `allow` scopés sur `teleport_dmz_cidr` (`10.255.255.248/29`) et `teleport_onprem_cidr` (`172.16.0.0/24`) — réutilisation des mêmes variables que pour le port 3025, plutôt que d'introduire un nouveau CIDR dédié.

**Pourquoi ces deux CIDR représentent "le VPN"**

Le tunnel OpenVPN site-to-site (`vpn_tunnel_network`, rôle `pfsense-cloud`) relie justement le LAN on-prem (`172.16.0.0/24`) et la DMZ cloud (`10.255.255.248/29`). Restreindre SSH à ces deux plages revient à n'accepter que le trafic qui transite par ce tunnel — combiné à la policy `default deny` du rôle `base`, toute autre source (y compris l'IP publique du Proxmox cloud) est rejetée.

**Risque de lockout — pas traité automatiquement**

Si l'opérateur est connecté en SSH brut depuis une IP hors de ces deux plages au moment du run, il perd l'accès SSH (mais pas Teleport, port 3022, non touché). Documenté dans `docs/architecture/bastion.md` comme précaution avant de jouer `teleport.yml`.

### Vérification

```bash
ansible bastion -i inventory/onprem.py -m shell -a "ufw status numbered" --become
```

---

## Rate limiting UFW sur le port 3022 (Teleport SSH proxy)

**Date :** 2026-06-23

### Contexte

fail2ban ne couvre que le port 22 (jail `sshd` standard, basé sur le format de log OpenSSH). Le port 3022, proxy SSH de Teleport, utilise son propre protocole et son propre format d'audit — pas de bruteforce-protection dessus malgré le fait qu'il soit exposé sur internet via DNAT.

### Décisions

**`ufw limit` plutôt qu'un filtre fail2ban custom**

Écrire un filtre fail2ban pour le format d'audit Teleport (JSON structuré, pas des lignes `auth.log`) est possible mais plus lourd à maintenir. `ufw limit` repose sur le module iptables `recent` : il bloque une IP source qui ouvre 6 connexions ou plus en 30 secondes, indépendamment du protocole — donc applicable à Teleport sans rien savoir de son format de log. Seul changement : `rule: allow` → `rule: limit` dans `roles/teleport/tasks/main.yml`.

**Pas appliqué au port 443 (web UI)**

`limit` ne distingue pas trafic légitime de malveillant — un navigateur ouvrant plusieurs connexions HTTP/2 en rafale pourrait se faire bloquer. Le risque de faux positif est plus élevé sur 443 (usage humain interactif) que sur 3022 (sessions SSH, moins fréquentes). Le port 443 reste en `allow` simple.

### Vérification

```bash
ansible bastion -i inventory/onprem.py -m shell -a "ufw status verbose" --become
```

doit montrer `3022/tcp LIMIT Anywhere`.

---

## Logs UFW expédiés vers Kibana via filebeat

**Date :** 2026-06-23

### Contexte

UFW (policy `default deny`, rôles `base`/`teleport`) rejette déjà du trafic indésirable, mais ces rejets ne sont loggés nulle part par défaut — aucune visibilité sur les tentatives bloquées (scan, bruteforce, erreurs de config).

### Décisions

**`ufw logging on` dans `base` (tous les hosts, pas seulement bastion)**

Le coût est négligeable (logs uniquement sur connexions effectivement filtrées) et utile partout, pas seulement sur l'host exposé à internet — ça peut aussi révéler du trafic interne anormal sur ops/services/web.

**Réutilisation de l'input `syslog` existant de filebeat plutôt qu'un nouvel input dédié**

`/var/log/ufw.log` est ajouté aux `paths` de l'input `filestream` `syslog` déjà présent dans `roles/filebeat/templates/filebeat.yml.j2` (qui suit déjà `/var/log/syslog` et `/var/log/auth.log`). Pas de nouveau rôle ni de module Elastic dédié — `ufw.log` existe déjà nativement via le drop-in rsyslog livré avec le paquet `ufw` (`/etc/rsyslog.d/20-ufw.conf`), donc rien à configurer côté rsyslog.

### Vérification

```bash
ansible ops:bastion:web -i inventory/onprem.py -m shell -a "tail -5 /var/log/ufw.log" --become
```

puis recherche `log.file.path: "/var/log/ufw.log"` dans Kibana.

---

## Attente cloud-init avant SSH dans deploy-remote.sh

**Date :** 2026-06-23

### Contexte

`wait_for_ssh()` dans `scripts/deploy-remote.sh` timeoutait à 120s sur bastion/website alors que les VMs n'avaient pas fini cloud-init (observé à 200s+ pour bastion — apt upgrade, kernel, bind9...). Le script échouait sur un faux problème ("inaccessible") alors qu'il fallait juste attendre.

### Décisions

**`wait_for_cloud_init()` via l'agent QEMU plutôt qu'augmenter bêtement le timeout SSH**

Augmenter le timeout de `wait_for_ssh` aurait masqué le problème sans le résoudre proprement (on devine une durée au lieu de vérifier l'état réel). À la place, une nouvelle fonction lance `cloud-init status --wait` via `agent/exec` (même mécanisme que `inject_ssh_key`/`configure_network`) et poll `agent/exec-status` jusqu'à la fin réelle de cloud-init (jusqu'à 10 min), insérée entre `configure_network` et `wait_for_ssh`. `wait_for_ssh` reste ensuite un filet de sécurité (timeout porté à 180s, largement suffisant une fois cloud-init confirmé terminé).

**Échec silencieux plutôt que bloquant si l'agent ne répond pas**

Si `agent/exec` ne renvoie pas de PID (cas limite, agent indisponible), la fonction continue sans bloquer le script — `wait_for_ssh` reste le dernier filet, pour ne pas introduire un nouveau point de blocage plus fragile que l'ancien.

### Vérification

Relancer `scripts/deploy-remote.sh` et observer dans les logs `"==> Attente fin cloud-init ..."` se terminer par `"cloud-init ... terminé."` avant que `wait_for_ssh` démarre.

---

## Déploiement VMs Cloud PVE2 — bridges et réseau

**Date :** 2026-06-01

### Contexte

Le déploiement des VMs cloud (`bastion`, `website`, `pfsense-cloud-01`) sur PVE2 a révélé trois problèmes distincts, résolus dans `scripts/deploy-remote.sh` et `terraform/envs/remote/`.

---

### Problème 1 — Mauvais bridges pour les VMs Cloud

Les bridges `vmbr1` (LAN on-prem, 172.16.0.1/24) et `vmbr2` (transit WAN pfSense, 10.0.0.1/30) étaient utilisés par les variables Terraform pour le Cloud. Les VMs cloud se retrouvaient sur les bridges on-prem avec des IPs incompatibles → pas d'ARP, pas de connectivité réseau.

**Décision :** Créer deux bridges dédiés Cloud créés au démarrage de `deploy-remote.sh` via SSH direct sur l'hôte Proxmox :

| Bridge | IP hôte | Réseau | Usage |
|---|---|---|---|
| `vmbr3` | `10.255.255.254/29` | `10.255.255.248/29` | Cloud DMZ — bastion |
| `vmbr4` | `192.168.255.254/28` | `192.168.255.240/28` | Cloud LAN — website + pfSense LAN |

**Pourquoi SSH direct et non l'API Proxmox ?**
L'API Proxmox `POST /nodes/{node}/network` + `PUT /nodes/{node}/network` enregistre les changements en "pending" mais ne les écrit pas dans `/etc/network/interfaces` de manière fiable. La création directe via SSH (`printf >> /etc/network/interfaces` + `ifup`) est déterministe.

La règle NAT pour le bastion (internet via Proxmox) est ajoutée via `iptables -t nat -A POSTROUTING -s 10.255.255.248/29 -o vmbr0 -j MASQUERADE`, persistée dans les stanzas `post-up`/`post-down` du bridge.

---

### Problème 2 — cloud-init génère `eth0`, Ubuntu 22.04 utilise `ens18`

Le provider bpg/proxmox génère les ISOs cloud-init en **format v1** (`version: 1`) avec le nom d'interface `eth0`. Ubuntu 22.04 utilise les noms d'interface prévisibles (`ens18`). Le netplan généré par cloud-init cible `eth0` → interface non trouvée → aucune IP assignée → fallback silencieux en DHCP (sans serveur DHCP, la VM reste sans IP).

**Symptôme :** `cloud-init status: done` mais `ens18` sans IPv4, uniquement link-local IPv6.

**Décision :** Injection de la configuration réseau via l'agent QEMU (`POST .../agent/exec`) après le boot, indépendamment de cloud-init. La fonction `configure_network()` dans `deploy-remote.sh` :

1. Génère un netplan v2 ciblant `ens18` encodé en base64 (évite les problèmes d'échappement JSON/shell dans le payload de l'agent)
2. L'injecte dans `/etc/netplan/99-static.yaml` via `echo | base64 -d`
3. Applique avec `netplan apply`
4. Force l'IP avec `ip addr add` + `ip route replace` en fallback si netplan est lent

```bash
configure_network "${VM_ID_BASTION}" "bastion" "${BASTION_IP}/29" "10.255.255.254"
configure_network "${VM_ID_WEBSITE}"  "website" "${WEBSITE_IP}/28" "192.168.255.254"
```

Cette approche est analogue à `inject_ssh_key` — cloud-init ne gère pas non plus correctement les clés SSH sur des users créés par autoinstall Ubuntu (voir décision *SSH key-only*).

**Pourquoi ne pas corriger le template Packer ?**
Ajouter `net.ifnames=0 biosdevname=0` au GRUB forcerait `eth0` sur toute l'infra, ce qui casserait les interfaces on-prem déjà opérationnelles. La correction côté agent QEMU est ciblée et n'affecte que le clone au boot.

---

### Problème 3 — Artefact de rebase dans `terraform/envs/remote/`

Le rebase de la branche cloud avait produit deux artefacts :

- **`main.tf`** : bloc `module "bastion"` sans `}` fermant, bloc `provider "proxmox"` intercalé (dupliqué avec `providers.tf`)
- **`variables.tf`** : 6 variables déclarées deux fois avec des valeurs par défaut contradictoires

`terraform validate` échouait immédiatement. Corrigé manuellement.

---

## Authentification SSH uniquement — suppression des passwords

**Date :** 2026-04-29
**Branche :** `remove-password-and-setup-ssh-key`

### Problème

Trois endroits avaient des passwords en dur ou transmis en clair dans le code :

1. **Packer Ubuntu** — `build_password` (cleartext "ubuntu") utilisé comme `ssh_password` pour le communicator Packer + dans le `user-data` autoinstall. `proxmox_password` utilisé comme `ssh_bastion_password`.
2. **Terraform cloud-init** — `vm_password` passé dans `user_account.password` sur toutes les VMs Ubuntu clonées.
3. **Ansible inventory** — `ansible_password: "pfsense"` en clair dans `onprem.yml`.

### Décision

**SSH key-only** sur toute l'infrastructure bootstrap. Une seule paire de clés (`~/.ssh/id_ed25519`) couvre tous les accès : Packer bastion, Terraform provider bpg, injection QEMU agent, Ansible.

### Pourquoi pas Ansible Vault ou un gestionnaire de secrets tiers ?

- **Ansible Vault** : cache le problème sans le résoudre. Un master password remplace les passwords — on reporte le problème.
- **HashiCorp Vault dès le bootstrap** : problème de bootstrap circulaire. Pour lire un secret depuis Vault, Vault doit être déployé. Pour déployer Vault, on a besoin de credentials.

**Vault intervient en Phase 2**, une fois PVE1 opérationnel : PKI pour les certs OpenVPN inter-sites, SSH secrets engine pour les accès VMs dynamiques, KV pour les secrets applicatifs.

### Implémentation finale

| Composant | Avant | Après |
|---|---|---|
| Packer Ubuntu communicator | `ssh_password = "ubuntu"` (stocké) | password éphémère généré dans deploy.sh, jamais stocké |
| Packer Ubuntu bastion | `ssh_bastion_password = proxmox_password` | `ssh_bastion_private_key_file = ~/.ssh/id_ed25519` |
| Packer Ubuntu user-data | `allow-pw: true` + hash stocké | `allow-pw: true` + hash éphémère + clé injectée en BLOC 3 |
| Packer Ubuntu (fin de build) | rien | BLOC 4 : `rm -rf ~/.ssh + passwd -l ubuntu` |
| Packer pfSense config.xml | pas de clé SSH | `<authorizedkeys>` base64 via templatefile |
| Terraform cloud-init | `user_account.password = vm_password` | supprimé — clé injectée par QEMU agent |
| Ansible inventory | `ansible_password: "pfsense"` + IPs hardcodées | script Python dynamique depuis config.env + ProxyJump |
| Terraform bpg/proxmox SSH | `password = proxmox_password` | `private_key = file(pathexpand(...))` |

### Pourquoi un password éphémère pour le communicator Packer Ubuntu ?

Première approche tentée : clé SSH injectée dans `ssh.authorized-keys` de l'autoinstall Ubuntu. Échec : race condition entre le montage des filesystems au reboot et la tentative de connexion Packer. Le serveur SSH est accessible mais `authorized_keys` n'est pas encore écrit ou a de mauvaises permissions.

Solution retenue : password éphémère (`openssl rand`) généré dans deploy.sh, exporté en mémoire, utilisé comme `ssh_password` par Packer. Jamais écrit nulle part. Le provisioner BLOC 3 injecte la clé SSH et désactive le password SSH. BLOC 4 efface le tout avant la conversion en template.

### Pourquoi QEMU agent pour l'injection de clé SSH sur les clones ?

cloud-init (via provider bpg/proxmox) n'injecte pas les clés SSH dans `authorized_keys` pour un user créé par autoinstall Ubuntu (subiquity). Cloud-init considère le user comme "déjà existant" et saute l'étape d'injection de clé.

Solution : après le `terraform apply`, deploy.sh utilise l'API Proxmox (`POST .../agent/exec`) pour écrire directement `authorized_keys` via le QEMU guest agent en cours d'exécution dans la VM.

### Pourquoi un inventaire Ansible dynamique (script Python) ?

L'inventaire YAML statique avait des IPs hardcodées qui divergeaient de config.env. Dès qu'une IP changeait dans config.env, l'inventaire devenait incorrect silencieusement.

Solution : `inventory/onprem.py` lit config.env à chaque exécution. IPs, ProxyJump et clé SSH sont toujours cohérents avec l'environnement déployé. Format JSON dynamique requis par Ansible (`--list` / `--host`).

---

## IPs des VMs PVE1 — passage de statique à DHCP

**Date :** 2026-04-29
**Branche :** `configure-vault`

### Problème

`config.env` exigeait de déclarer `VM_IP_SERVICES` et `VM_IP_OPS` avant le déploiement. Ces IPs étaient passées à Terraform qui les injectait dans cloud-init. Problème : pfSense est déployé **avant** les VMs Ubuntu (phase 1 Terraform), et c'est son DHCP qui gouverne le LAN `172.16.0.0/24`. Il est impossible de garantir à l'avance quelle IP sera assignée — le pool DHCP peut avoir changé, la plage peut varier selon l'environnement, et forcer une IP statique crée des conflits si une autre VM a déjà obtenu cette adresse.

### Décision

Les VMs `ops-vm` et `services-vm` utilisent **DHCP** (`address = "dhcp"` dans cloud-init). L'IP réelle est découverte dynamiquement après le boot via l'API QEMU guest agent de Proxmox, sans aucune valeur hardcodée.

### Implémentation

| Composant | Avant | Après |
|---|---|---|
| `modules/ops-vm/main.tf` | `address = var.vm_ip_cidr` | `address = "dhcp"` |
| `modules/services-vm/main.tf` | `address = var.vm_ip_cidr` | `address = "dhcp"` |
| `modules/*/outputs.tf` | `split("/", var.vm_ip_cidr)[0]` | `proxmox_virtual_environment_vm.*.ipv4_addresses` |
| `deploy.sh` | `OPS_IP="${VM_IP_OPS%%/*}"` | `get_vm_ip()` via `/agent/network-get-interfaces` |
| `inventory/onprem.py` | `env.get("VM_IP_OPS")` | `os.environ.get("OPS_IP") or env.get("VM_IP_OPS")` |
| `config.env` | `VM_IP_SERVICES`, `VM_IP_OPS` requis | supprimés |

### Comment `get_vm_ip()` fonctionne

Après `wait_for_agent`, `deploy.sh` appelle l'endpoint Proxmox `GET /nodes/{node}/qemu/{vmid}/agent/network-get-interfaces`. Le QEMU guest agent retourne toutes les interfaces réseau de la VM avec leurs IPs. La fonction filtre `lo`, les adresses loopback (`127.x`) et link-local (`169.254.x`), et retourne la première IPv4 valide trouvée.

L'IP est exportée dans `$OPS_IP` / `$SERVICES_IP` avant le lancement d'Ansible. `inventory/onprem.py` lit ces variables d'environnement en priorité.

### Lancement Ansible manuel sans `deploy.sh`

Si tu relances Ansible seul (hors deploy complet), exporte les IPs à la main d'abord :

```bash
export OPS_IP=172.16.0.x
export SERVICES_IP=172.16.0.y
ansible-playbook playbooks/vault.yml -i inventory/onprem.py
```

Ou renseigne `VM_IP_OPS` / `VM_IP_SERVICES` dans `config.env` comme fallback — `onprem.py` les lira si les variables d'env ne sont pas définies.

### Voir aussi

- `docs/architecture/ssh-auth.md` — flux complet d'authentification SSH

---

## Packer pfSense — Golden Image

### Pourquoi Packer pour pfSense ?

pfSense n'a pas de mécanisme de cloud-init. L'installation manuelle est répétitive et sujette à l'erreur humaine. Packer automatise l'installation via `boot_command` (séquence de touches clavier simulées) et injecte la configuration via un CD virtuel contenant `config.xml`.

### Workflow du build (ID template : 2000)

1. Packer crée une VM temporaire (2 vCPUs, 2 Go RAM, VirtIO, disque 10 Go)
2. Monte l'ISO pfSense 2.7.2 et simule la séquence d'installation (UFS, disque entier)
3. Ouvre un shell FreeBSD post-install et copie `config.xml` depuis le CD de configuration
4. Éteint la VM — Proxmox la convertit en template ID 2000

### Ce que configure config.xml

| Paramètre | Valeur |
|---|---|
| WAN interface | `vtnet0` (vmbr2) |
| LAN interface | `vtnet1` (vmbr1) |
| LAN IP | `172.16.0.254/24` |
| DHCP range | `172.16.0.241` → `172.16.0.253` |
| DNS | `1.1.1.1`, `8.8.8.8` |
| SSH | Activé |
| Clé SSH admin | Injectée en base64 depuis `SSH_PUBLIC_KEY` (config.env) |

`config.xml` est un template Packer (`config.xml.pkrtpl.hcl`) — la clé SSH est injectée dynamiquement via `base64encode(var.pfsense_admin_ssh_public_key)`.

### Pourquoi `communicator = "none"` pour pfSense ?

pfSense (FreeBSD) n'a pas Python ni d'environnement compatible avec les provisioners Packer. Toute la configuration est faite via le CD virtuel. Aucune connexion SSH post-install n'est nécessaire.

---

## HTTPS sur tous les services — PKI interne

**Date :** 2026-05-27

### Problème

L'infrastructure tournait entièrement en HTTP non chiffré (Vault, Elasticsearch, Kibana, Filebeat). Les credentials circulaient en clair sur le réseau privé.

### Décision

Tout passe en **HTTPS** via une CA interne générée par Ansible (`community.crypto`). Pas de Let's Encrypt : aucun domaine public n'est associé à l'infra.

### Pourquoi une CA interne et non Let's Encrypt ?

Les services sont sur des IPs privées (172.16.0.x, 10.255.255.x) et les domaines `op.local` / `cloud.local` ne sont pas routables publiquement. Let's Encrypt nécessite soit un challenge HTTP-01 (port 80 accessible depuis internet) soit DNS-01 (API d'un registrar DNS). Aucun des deux n'est disponible.

Solution : CA auto-signée générée par le rôle Ansible `tls` via `community.crypto`. La CA est stockée localement sur le controller Ansible (`~/.ansible-tls/`) — jamais dans le repo.

### Implémentation

| Composant | Avant | Après |
|-----------|-------|-------|
| Vault listener | `tls_disable = true` | TLS avec certs `/vault/certs/` |
| Elasticsearch | HTTP | HTTPS + xpack.security.http.ssl |
| Kibana | HTTP | HTTPS + server.ssl |
| Filebeat output | `http://es:9200` | `https://es:9200` + ca_path |
| Vault URI Ansible | `http://` | `https://` + ca_path |

SANs par host configurés dans `inventory/host_vars/` (IP + DNS).

---

## Kibana séparé d'ops-vm — gestion du disque

**Date :** 2026-05-27

### Problème

ops-vm (7.6G disk) atteignait 100% avec ES (1.88GB) + Vault (612MB) + Kibana (1.73GB). Kibana étant le plus grand et le moins critique pour les opérations, il a été déplacé.

### Décision

Kibana tourne sur **bastion** (PVE2 Cloud) en tant que service standalone dans son propre Docker Compose. Il se connecte à Elasticsearch via HTTPS à travers le tunnel VPN inter-sites.

Avantage supplémentaire : Kibana est maintenant dans la DMZ Cloud (10.255.255.x), séparé physiquement d'Elasticsearch.

### Pourquoi bastion et non web ?

- web n'a pas Docker installé (et a des problèmes de connectivité internet pour l'installation)
- bastion héberge déjà le rôle base (Docker, UFW) — coût d'ajout nul

---

## Filebeat direct vers Elasticsearch — suppression de Logstash

**Date :** 2026-05-27

### Problème

La stack ELK initiale incluait Logstash comme pipeline intermédiaire (Filebeat → Logstash → ES). Logstash ne remplissait aucune fonction de transformation — il ne faisait que forwarder les logs.

### Décision

Suppression de Logstash. Filebeat envoie directement vers Elasticsearch via HTTPS.

Gain : ~600MB d'image Docker en moins sur ops-vm. Configuration simplifiée.

---

## Gestion disque — ILM + rotation logs

**Date :** 2026-05-27

### Problème

Toutes les VMs ont 7.6G de disque. Les images Docker seules consomment 2-4GB selon la VM. Sans politique de rétention, Elasticsearch et les logs système peuvent remplir le disque en quelques semaines.

### Décision

Trois niveaux de protection :

1. **ILM Elasticsearch** : politique `filebeat-policy` — rollover à 1GB ou 7 jours, suppression après 30 jours. Appliquée lors du déploiement ELK.

2. **Rotation logs Docker** : `log-driver: json-file`, `max-size: 10m`, `max-file: 3` dans `/etc/docker/daemon.json`. Configuré via le rôle `base`.

3. **Nettoyage periodique** : `apt-get clean` + `journalctl --vacuum-size=100M` dans le rôle `base`.

La config Docker daemon est centralisée dans le rôle `base` (DNS + log rotation). Le rôle `vault` ne gère plus `daemon.json`.

---

## Stack ELK sur ops-vm — centralisation des logs

**Date :** 2026-05-03
**Branche :** `adding-stack-ELK`

### Problème

L'infrastructure n'avait aucune visibilité sur ce qui se passait sur les VMs : pas de logs centralisés, pas d'interface de recherche, pas d'alerting possible. Diagnostiquer un problème nécessitait de se connecter en SSH sur chaque VM et de lire les fichiers de logs manuellement.

### Décision

Déployer la stack ELK (Elasticsearch + Logstash + Kibana) en **Docker Compose sur ops-vm**, avec Filebeat sur `services-vm` pour l'envoi des logs.

### Pourquoi ELK et pas une alternative ?

- **ELK** (Elastic Stack) : standard de l'industrie pour la centralisation de logs. Kibana fournit une UI de recherche et visualisation complète. Large adoption = documentation abondante.
- **Loki + Grafana** : alternative plus légère, mais Loki est un agrégateur de logs sans indexation full-text native — moins adapté pour rechercher dans des logs structurés.
- **Graylog** : bonne alternative mais dépend de MongoDB + Elasticsearch, donc plus lourd que ELK seul.

ELK couvre les besoins du lab : ingestion, indexation, recherche, visualisation.

### Pourquoi Docker Compose pour ELK et non des packages système ?

Les packages apt Elastic nécessitent des configurations système complexes (JVM, systemd units, certificats). Docker Compose permet de :

- Versionner l'ensemble de la configuration dans un seul fichier `docker-compose.yml`
- Démarrer/arrêter/mettre à jour les 3 services en une commande
- Isoler les processus ELK du système hôte
- Gérer les dépendances de démarrage (ES doit être `green` avant que Logstash et Kibana démarrent) via `healthcheck` + `depends_on: condition: service_healthy`

### Pourquoi Vault et ELK sur la même VM (ops-vm) ?

Le lab tourne sur un seul Proxmox avec des ressources limitées. Créer une VM dédiée pour ELK gaspillerait le budget RAM/CPU. Les deux stacks partagent le même socle Docker et la même VM avec 4 vCPUs et 8 Go de RAM.

Vault tourne en **container Docker standalone** (pas dans le Compose ELK) pour rester indépendant — un `docker compose restart` ne touche pas Vault.

### Pourquoi pas Docker-in-Docker (DinD) ?

DinD (un container Docker qui contient d'autres containers) est un anti-pattern : problèmes de sécurité (privilèges étendus), complexité réseau, isolation incorrecte. La bonne approche est d'utiliser Docker Compose directement sur l'hôte pour les groupes de services liés.

### Problème disque — partition non étendue sur clone Ubuntu

**Symptôme** : `no space left on device` lors du `docker pull` des images ELK, alors que le disque Proxmox était bien configuré à 30 Go dans Terraform.

**Cause** : Le template Ubuntu a une partition de 8 Go. Quand Terraform clone le template avec `size = 30`, Proxmox redimensionne le disque virtuel (le fichier `.qcow2` devient 30 Go), mais **les partitions et le filesystem à l'intérieur de la VM restent à 8 Go**. cloud-init avec le module `growpart` était censé gérer ça, mais ne s'est pas déclenché sur ce clone.

**Solution** : `deploy.sh` exécute `growpart` + `pvresize` + `lvextend` + `resize2fs` via SSH immédiatement après `wait_for_ssh`, avant le lancement d'Ansible :

```bash
extend_disk() {
  local host="$1"
  ssh ... ubuntu@"${host}" "
    sudo growpart /dev/vda 3 2>/dev/null || true
    sudo pvresize /dev/vda3 2>/dev/null || true
    sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv 2>/dev/null || true
    sudo resize2fs /dev/ubuntu-vg/ubuntu-lv 2>/dev/null || true
  "
}
```

Cette séquence fonctionne sur le layout LVM standard d'Ubuntu 22.04 autoinstall (`/dev/vda3` → PV LVM → `ubuntu-vg/ubuntu-lv`).

### Architecture des containers sur ops-vm

```
ops-vm (172.16.0.242)
│
├── vault (Docker standalone)
│     hashicorp/vault:latest
│     Port: 8200
│     Volume: /opt/vault/data → /vault/file
│
└── elk-net (Docker network)
      ├── elasticsearch (elasticsearch:8.13.0)
      │     Port: 9200, 9300
      │     Volume: /opt/elk/elasticsearch/data → /usr/share/elasticsearch/data
      │     Healthcheck: GET /_cluster/health?wait_for_status=green
      │
      ├── logstash (logstash:8.13.0)   [démarre après ES green]
      │     Port: 5044 (Beats input)
      │     Pipeline: syslog tag → index logstash-YYYY.MM.dd
      │
      └── kibana (kibana:8.13.0)       [démarre après ES green]
            Port: 5601
```

### Flux de logs

```
services-vm
  └── Filebeat
        ├── input: /var/log/syslog
        └── input: /var/lib/docker/containers/**/*.log
              │
              │  TCP 5044 (Beats protocol)
              ▼
ops-vm — Logstash (port 5044)
  └── pipeline.conf : beats input → elasticsearch output
              │
              ▼
        Elasticsearch (port 9200)
        index: logstash-YYYY.MM.dd
              │
              ▼
        Kibana (port 5601)
        Data view: logstash-*
```

### Résolution dynamique de l'IP ops-vm pour Filebeat

Filebeat sur `services-vm` doit connaître l'IP de Logstash sur `ops-vm`. Cette IP est assignée par DHCP et peut changer à chaque déploiement. Le playbook `filebeat.yml` la résout dynamiquement :

```yaml
- name: Gather ops-vm facts for logstash host resolution
  hosts: ops
  gather_facts: true

- name: Deploy Filebeat
  hosts: services
  vars:
    elk_logstash_host: "{{ hostvars[groups['ops'][0]]['ansible_host'] }}"
```

`ansible_host` de ops-vm (lu depuis l'inventaire dynamique, lui-même lu depuis `$OPS_IP` ou `config.env`) est injecté dans `filebeat.yml.j2` comme destination Logstash. Aucune IP hardcodée nulle part.

### Renommage vault-vm → ops-vm

La VM s'appelait initialement `vault-vm` car elle n'hébergeait que Vault. Après l'ajout de la stack ELK, ce nom ne reflétait plus son contenu. Elle a été renommée `ops-vm` (operations VM) : terme générique qui couvre les services transverses (secrets management + observabilité) sans être lié à un outil spécifique.

Fichiers modifiés lors du renommage :
- `terraform/modules/vault-vm/` → `terraform/modules/ops-vm/`
- Toutes les références `vault_vm` → `ops_vm` dans Terraform
- Variable config.env `VM_ID_VAULT` → `VM_ID_OPS`
- Groupe Ansible `vault` → `ops`, host `vault-vm` → `ops-vm`
- Variable d'environnement `VAULT_IP` → `OPS_IP` dans deploy.sh et workflow CI

---

## Elastic Agent + Fleet Server — remplacement de Filebeat

**Date :** 2026-05-04
**Branche :** `adding-stack-ELK`

### Problème

Filebeat est limité aux logs fichiers. Il ne collecte pas les métriques système (CPU, RAM, réseau) ni les security events. Chaque agent Filebeat est configuré individuellement via Ansible — pas de supervision centralisée de l'état des agents.

### Décision

Remplacer Filebeat par **Elastic Agent** géré via **Kibana Fleet**. Le Fleet enrollment token est stocké dans HashiCorp Vault pour ne jamais circuler en clair.

### Architecture

| Composant | Rôle | Localisation |
|---|---|---|
| `fleet-server` | Gère les Elastic Agents | container Docker dans elk-net (ops-vm) |
| `elastic-agent` | Collecte logs + métriques | apt sur ops-vm et services-vm |
| Vault KV | Stocke le Fleet enrollment token | `secret/data/elk/fleet-enrollment-token` |

### Pourquoi Fleet Server dans le Compose ELK et non en container séparé ?

Fleet Server fait partie de la stack Elastic — même cycle de vie, même réseau Docker `elk-net`, même image (`elastic-agent`). L'intégrer dans le Compose évite un container standalone à gérer séparément.

### Pourquoi Elastic Agent installé via apt (hôte) plutôt qu'en container Docker ?

Un Elastic Agent en container ne peut pas facilement accéder aux logs des autres containers Docker du host (`/var/lib/docker/containers/**`) ni aux métriques système sans monter de nombreux volumes en lecture-only avec des permissions complexes. Installé via apt sur le host, l'agent accède nativement à tout le système.

### Pourquoi le token passe par Vault et non par une variable d'env ou un fichier ?

Le token Fleet est un secret qui permet d'enrôler n'importe quel agent dans la stack. Le stocker dans une variable d'env (config.env ou CI) l'expose dans les logs et l'historique shell. Le stocker dans Vault le rend accessible uniquement aux playbooks qui s'authentifient avec le root token — lui-même stocké dans `/root/vault-init.json` accessible uniquement à root sur ops-vm.

### Séquence d'enrollment

```
elk.yml
  └── Fleet Server démarre dans le Compose
        └── Kibana Fleet s'initialise (POST /api/fleet/setup)
              └── Token récupéré via GET /api/fleet/enrollment_api_keys
                    └── Token écrit dans Vault KV

elastic-agent.yml
  └── Lit token depuis Vault (slurp vault-init.json → root token → GET /v1/secret/...)
        └── elastic-agent enroll --url fleet-server --token ... --insecure
              └── elastic-agent service démarré
```

### Pièges gérés

| Piège | Fix |
|---|---|
| Fleet setup Kibana pas encore prêt | `retries: 30` / `delay: 10` sur POST /api/fleet/setup |
| Token vide si Fleet pas initialisé | `until: items | length > 0` sur GET enrollment_api_keys |
| `elastic-agent enroll` non idempotent | Vérification de `elastic-agent status` avant enrollment — skip si `Healthy` |
| Vault non unsealed au moment du rôle elk | Vault est initialisé et unsealed par vault.yml avant que elk.yml tourne |
| KV engine déjà monté dans Vault | `status_code: [200, 204, 400]` — 400 = déjà monté, ignoré |

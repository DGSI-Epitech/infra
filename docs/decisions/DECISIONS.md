# Decisions

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

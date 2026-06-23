# Teleport — Déploiement via Ansible

Ce document explique comment déployer Teleport sur `services-vm` via Ansible et comment y accéder depuis son ordi.

---

## Contexte

Teleport est une plateforme d'accès sécurisé qui remplace le bastion SSH classique. Il expose une **web UI** et permet de se connecter aux VMs du LAN interne sans exposer le port 22 directement sur internet.

```
Ton ordi (internet)
    │
    ▼
Proxmox (51.75.128.134) ← tunnel SSH
    │
    ▼
services-vm (172.16.0.242) ← Teleport
    │
    ├── ops-vm     (172.16.0.11)
    └── autres VMs du LAN
```

---

## Structure des fichiers

```
ansible/
├── roles/
│   └── teleport/
│       ├── tasks/
│       │   └── main.yml
│       └── templates/
│           └── teleport.yaml.j2
└── playbooks/
    └── teleport.yml
```

---

## Fonctionnement du role

### `tasks/main.yml`

**1. Ajout de la clé GPG**
```yaml
- name: Add Teleport GPG key
  shell: |
    curl https://apt.releases.teleport.dev/gpg | gpg --dearmor -o /usr/share/keyrings/teleport-archive-keyring.gpg
  args:
    creates: /usr/share/keyrings/teleport-archive-keyring.gpg
```
Télécharge et convertit la clé GPG de Teleport au format binaire attendu par apt. Le `creates:` évite de réexécuter si le fichier existe déjà.

**2. Ajout du repo apt**
```yaml
- name: Add Teleport apt repo
  shell: |
    echo "deb [signed-by=/usr/share/keyrings/teleport-archive-keyring.gpg] https://apt.releases.teleport.dev/ubuntu jammy stable/v14" > /etc/apt/sources.list.d/teleport.list
  args:
    creates: /etc/apt/sources.list.d/teleport.list
```
Ajoute le repo officiel Teleport pour qu'apt sache où télécharger le paquet.

**3. Installation**
```yaml
- name: Install Teleport
  apt:
    name: teleport
    update_cache: yes
    state: present
```
Installe Teleport via apt.

**4. Déploiement de la config**
```yaml
- name: Deploy Teleport config
  template:
    src: teleport.yaml.j2
    dest: /etc/teleport.yaml
    owner: root
    group: root
    mode: '0600'
```
Copie le fichier de configuration sur la VM. `mode: '0600'` = seul root peut lire le fichier (équivalent `chmod 600`).

**5. Démarrage du service**
```yaml
- name: Enable and start Teleport
  systemd:
    name: teleport
    enabled: yes
    state: started
```
Active Teleport au démarrage et le démarre.

**6. Attente que Teleport soit prêt**
```yaml
- name: Wait for Teleport auth service to be ready
  wait_for:
    port: 3025
    host: 127.0.0.1
    delay: 5
    timeout: 30
```
Attend que le port `3025` (auth service) soit ouvert avant de continuer. Sans ça, la création d'utilisateur échoue car Teleport n'est pas encore prêt.

**7. Création de l'utilisateur admin**
```yaml
- name: Create Teleport admin user
  shell: |
    tctl users add admin --roles=editor,access --logins=ubuntu
  register: teleport_user
  ignore_errors: yes
```
Crée l'utilisateur admin. `register` capture la sortie de la commande dans `teleport_user`. `ignore_errors: yes` évite que le playbook échoue si l'utilisateur existe déjà.

**8. Affichage du lien d'invitation**
```yaml
- name: Show Teleport invite link
  debug:
    msg: "{{ teleport_user.stdout }}"
```
Affiche le lien d'invitation généré par Teleport dans la sortie Ansible.

---

## Configuration Teleport

### `templates/teleport.yaml.j2`

```yaml
teleport:
  nodename: services-vm        # Nom de cette machine dans Teleport
  data_dir: /var/lib/teleport  # Stockage des données (certificats, sessions...)
  log:
    output: stderr             # Logs visibles via journalctl -u teleport
    severity: INFO

auth_service:
  enabled: yes                 # Gère les utilisateurs et les certificats SSH

proxy_service:
  enabled: yes
  web_listen_addr: "0.0.0.0:3080"      # Port de la web UI
  public_addr: "172.16.0.242:3080"     # Adresse utilisée pour construire les liens

ssh_service:
  enabled: yes
  listen_addr: "0.0.0.0:3022"          # Port SSH de Teleport (≠ port 22)
```

---

## Lancer le déploiement

```bash
cd ansible
ansible-playbook playbooks/teleport.yml -i inventory/onprem.py
```

À la fin du playbook, le lien d'invitation s'affiche dans la sortie :

```
ok: [services-vm] => {
    "msg": "User admin has been created...\nhttps://172.16.0.242:3080/web/invite/TOKEN"
}
```

---

## Accéder à la web UI

`172.16.0.242` est sur le réseau privé LAN, inaccessible directement depuis internet. Il faut passer par un tunnel SSH via Proxmox :

```
Ton ordi ❌──────────────────────→ 172.16.0.242 (réseau privé)
Ton ordi ✅→ Proxmox (51.x.x.x) → 172.16.0.242 (même LAN)
```

**Ouvre le tunnel dans un terminal :**
```bash
ssh -L 3080:172.16.0.242:3080 -N root@51.75.128.134
```

- `-L 3080:172.16.0.242:3080` → redirige `localhost:3080` vers `172.16.0.242:3080` via Proxmox
- `-N` → ne pas ouvrir de shell, juste le tunnel

**Ouvre dans ton navigateur :**
```
https://localhost:3080
```

Accepte le certificat auto-signé et connecte-toi avec le compte `admin`.

---

## Ports utilisés

| Port | Service | Description |
|------|---------|-------------|
| 3080 | Proxy | Web UI + API |
| 3022 | SSH node | Connexions SSH via Teleport |
| 3025 | Auth | Communication interne Teleport |

---

## Durcissement — fail2ban (port 22)

Le bastion est le seul host exposé sur internet (Teleport :443 et :3022 via DNAT). Le rôle `base` ouvre aussi le port 22 (SSH brut, utilisé par Ansible pour l'administration) sans protection anti-bruteforce. Le rôle `fail2ban` comble ce trou.

### Structure des fichiers

```
ansible/
├── roles/
│   └── fail2ban/
│       ├── defaults/main.yml
│       ├── handlers/main.yml
│       ├── tasks/main.yml
│       └── templates/jail.local.j2
└── playbooks/
    └── teleport.yml   # roles: base, tls, teleport, fail2ban
```

### Fonctionnement

`tasks/main.yml` :
1. `apt install fail2ban`
2. déploie `templates/jail.local.j2` → `/etc/fail2ban/jail.local` (notify: `Restart fail2ban`)
3. active + démarre le service `fail2ban`

`templates/jail.local.j2` :
```ini
[DEFAULT]
bantime  = {{ fail2ban_bantime }}    # 1h par défaut
findtime = {{ fail2ban_findtime }}   # 10m par défaut
maxretry = {{ fail2ban_maxretry }}   # 5 tentatives
ignoreip = {{ fail2ban_ignoreip }}   # 127.0.0.1/8 ::1
banaction = ufw

[sshd]
enabled  = true
port     = ssh
backend  = systemd
```

Variables surchargeables dans `roles/fail2ban/defaults/main.yml` (`fail2ban_bantime`, `fail2ban_findtime`, `fail2ban_maxretry`, `fail2ban_ignoreip`).

### Pourquoi `banaction = ufw` plutôt que l'action par défaut (iptables)

Le firewall du repo est piloté entièrement via `community.general.ufw` (rôles `base`, `teleport`). L'action par défaut de fail2ban manipule directement des chaînes iptables custom (`f2b-sshd`), ce qui peut entrer en conflit d'ordonnancement avec les chaînes gérées par UFW. `banaction = ufw` fait passer fail2ban par `ufw insert ... deny from <ip>`, dans le même système que le reste du repo.

### Pourquoi seulement le jail `sshd` (port 22) dans cette passe

Le port 22 est exposé en interne (LAN/DMZ, utilisé par Ansible) — c'est la cible naturelle du jail `sshd` standard de fail2ban, qui parse les échecs d'authentification OpenSSH.

Le port 3022 (proxy SSH Teleport, exposé sur internet via DNAT) n'est **pas couvert** : Teleport a son propre protocole et son propre format de log d'audit, pas des lignes `auth.log`/journald façon OpenSSH. Un jail fail2ban dédié demanderait un filtre custom sur les events d'audit Teleport. La voie plus naturelle pour throttle ce port est la fonctionnalité native `connection_limits` de Teleport (`teleport.yaml`) — pas encore configurée, à traiter séparément.

### Vérification

```bash
ansible bastion -i inventory/onprem.py -m shell -a "fail2ban-client status sshd" --become
```

doit lister le jail `sshd` comme actif. Après un ban réel :

```bash
ansible bastion -i inventory/onprem.py -m shell -a "ufw status numbered" --become
```

doit montrer une règle `deny` insérée par fail2ban pour l'IP bannie.

---

## Durcissement — SSH (22) restreint au VPN site-to-site

En plus de fail2ban, le port 22 n'est plus ouvert au monde : le rôle `teleport` retire la règle `allow 22` posée par `base` (sans restriction de source) et la remplace par deux règles scoping, dans `tasks/main.yml` (section FIREWALL) :

```yaml
- name: Remove unrestricted SSH rule added by base role
  community.general.ufw:
    rule: allow
    port: "22"
    proto: tcp
    delete: true

- name: Allow SSH from Cloud DMZ ({{ teleport_dmz_cidr }})
  community.general.ufw:
    rule: allow
    port: "22"
    proto: tcp
    src: "{{ teleport_dmz_cidr }}"

- name: Allow SSH from on-prem LAN via VPN ({{ teleport_onprem_cidr }})
  community.general.ufw:
    rule: allow
    port: "22"
    proto: tcp
    src: "{{ teleport_onprem_cidr }}"
```

`teleport_dmz_cidr` (`10.255.255.248/29`) et `teleport_onprem_cidr` (`172.16.0.0/24`) sont les deux mêmes variables déjà utilisées pour restreindre le port auth 3025 — ce sont exactement les deux LAN reliés par le tunnel OpenVPN site-to-site (pfSense OP ↔ pfSense Cloud). Avec la policy `default deny` du rôle `base`, toute connexion SSH qui n'arrive pas via ce tunnel (donc depuis l'IP source du LAN on-prem ou de la DMZ cloud) est rejetée — y compris depuis l'IP publique du Proxmox cloud elle-même.

**Risque à connaître avant de jouer le playbook** : si tu es connecté en SSH directement depuis une IP hors DMZ/on-prem (pas via le VPN), cette règle te coupe l'accès SSH brut. Garder une session Teleport active (port 3022, non affecté) comme filet de sécurité avant d'appliquer.

### Vérification

```bash
ansible bastion -i inventory/onprem.py -m shell -a "ufw status numbered" --become
```

ne doit plus montrer de règle `22/tcp ALLOW Anywhere` — seulement les deux règles scoping sur `10.255.255.248/29` et `172.16.0.0/24`.

---

## Durcissement — rate limiting sur le port 3022 (Teleport SSH proxy)

fail2ban (voir plus haut) ne protège que le port 22 : il a besoin de parser des lignes de log façon OpenSSH, et Teleport a son propre format d'audit que le filtre `sshd` ne comprend pas. Pour le port 3022 (proxy SSH Teleport, exposé sur internet via DNAT), on utilise `ufw limit` plutôt que `ufw allow` — dans `roles/teleport/tasks/main.yml` :

```yaml
- name: Allow Teleport SSH proxy port (3022) with connection rate limiting
  community.general.ufw:
    rule: limit
    port: "{{ teleport_proxy_ssh_port | string }}"
    proto: tcp
```

### Comment ça marche

`ufw limit` s'appuie sur le module iptables `recent` : il compte les nouvelles connexions par IP source, et si une IP en fait **6 ou plus en 30 secondes**, les suivantes sont rejetées jusqu'à ce que le débit retombe. Contrairement à fail2ban, ça ne lit aucun log applicatif — juste le débit de connexions au niveau réseau, donc ça fonctionne indépendamment du protocole (Teleport, SSH brut, ou autre).

**Exemple** : un scan automatisé tente 20 connexions en 10s sur 3022 → les 5 premières passent, la 6e et les suivantes sont bloquées tant que le rythme ne retombe pas sous le seuil sur une fenêtre glissante de 30s.

**Compromis** : `limit` ne distingue pas trafic légitime et malveillant — un script qui ouvre plusieurs sessions `tsh ssh` en rafale peut se faire bloquer temporairement aussi. C'est pour ça que `443` (web UI, plusieurs connexions HTTP/2 simultanées par navigateur) reste en `allow` simple, et que seul 3022 passe en `limit`.

### Vérification

```bash
ansible bastion -i inventory/onprem.py -m shell -a "ufw status verbose" --become
```

doit montrer `3022/tcp LIMIT Anywhere` (au lieu de `ALLOW`).

---

## Durcissement — logs UFW vers Kibana

Les connexions rejetées par UFW (policy `default deny`) ne sont pas loguées par défaut. Le rôle `base` active le logging UFW, et le rôle `filebeat` expédie ces logs vers Elasticsearch comme le reste des logs système.

**`roles/base/tasks/main.yml`** (juste après l'activation d'UFW) :
```yaml
- name: Enable UFW logging
  community.general.ufw:
    logging: "on"
```

**`roles/filebeat/templates/filebeat.yml.j2`** — `/var/log/ufw.log` ajouté à l'input `syslog` existant :
```yaml
  - type: filestream
    id: syslog
    paths:
      - /var/log/syslog
      - /var/log/auth.log
      - /var/log/ufw.log
```

### Pourquoi ça suffit sans configurer rsyslog

`ufw.log` est déjà écrit par défaut sur Ubuntu : le paquet `ufw` installe son propre drop-in rsyslog (`/etc/rsyslog.d/20-ufw.conf`) qui route les lignes `[UFW ...]` vers ce fichier (et les arrête là, pas de doublon dans `syslog`). Comme `rsyslog` tourne déjà (`/var/log/syslog`/`auth.log` sont déjà suivis par filebeat aujourd'hui), il n'y a rien d'autre à installer — juste activer le logging UFW et ajouter le chemin du fichier à filebeat.

Appliqué sur tous les hosts (`base`/`filebeat` sont partagés), pas seulement le bastion : utile pour repérer du scan/bruteforce sur n'importe quelle VM, pas juste celle exposée à internet.

### Vérification

```bash
ansible ops:bastion:web -i inventory/onprem.py -m shell -a "tail -5 /var/log/ufw.log" --become
```

puis, dans Kibana, chercher `log.file.path: "/var/log/ufw.log"`.
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
    ├── vault-vm     (172.16.0.11)
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
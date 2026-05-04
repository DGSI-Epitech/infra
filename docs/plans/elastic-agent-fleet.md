# Plan — Elastic Agent + Fleet Server + Vault

**Branche cible :** `adding-elastic-agent-fleet`
**Statut :** non commencé

---

## Objectif

Remplacer Filebeat (actuel, limité aux logs fichiers) par **Elastic Agent** — l'agent unifié Elastic qui collecte logs + métriques + security data en un seul binaire.

Géré centralement depuis **Kibana Fleet**. Le token d'enrollment est stocké dans **HashiCorp Vault** pour ne jamais circuler en clair dans le code ou les variables d'environnement.

---

## Architecture cible

```
ops-vm (172.16.0.242)
├── vault (Docker standalone, port 8200)
│     └── secret/elk/fleet-enrollment-token  ← token stocké ici
│
└── elk-net (Docker Compose)
      ├── elasticsearch  (port 9200)
      ├── logstash       (port 5044)   ← gardé pour compatibilité
      ├── kibana         (port 5601)
      └── fleet-server   (port 8220)   ← NOUVEAU
            └── gère les Elastic Agents

services-vm (172.16.0.241)
└── elastic-agent                      ← remplace Filebeat
      ├── logs système (/var/log/syslog, /var/log/auth.log)
      ├── logs Docker (/var/lib/docker/containers/**/*.log)
      └── métriques système (CPU, RAM, disque, réseau)

ops-vm (lui-même)
└── elastic-agent                      ← NOUVEAU
      ├── logs Vault container
      ├── logs ELK containers
      └── métriques système
```

---

## Ordre de déploiement (deploy.sh / CI)

```
1. vault.yml          → Vault init + unseal (déjà en place)
2. elk.yml            → ELK + Fleet Server + génération tokens + écriture dans Vault
3. elastic-agent.yml  → Lecture token depuis Vault + enrollment agents
4. (filebeat.yml)     → SUPPRIMÉ, remplacé par elastic-agent.yml
```

---

## Point technique critique — xpack.security

Notre ES tourne avec `xpack.security.enabled: false`. Fleet Server en 8.x fonctionne sans sécurité en mode insecure uniquement si on passe les bonnes variables d'env au container.

**Sans activation security :**
- Le endpoint `/_security/service/*/credential/token/*` n'existe pas → pas de service token classique
- Fleet Server peut démarrer en mode `FLEET_SERVER_INSECURE_HTTP=1` + `FLEET_SERVER_ELASTICSEARCH_INSECURE=1`
- L'enrollment token est récupérable via l'API Kibana Fleet : `GET /api/fleet/enrollment_api_keys`

**Option retenue pour le lab : security désactivée + mode insecure Fleet.**
Si besoin de sécuriser : activer `xpack.security.enabled: true` + configurer un password ES (décision future, hors scope).

---

## Fichiers à créer / modifier

### NOUVEAU — `ansible/roles/elastic-agent/`

```
roles/elastic-agent/
├── defaults/main.yml
├── tasks/main.yml
└── handlers/main.yml
```

#### `defaults/main.yml`

```yaml
elastic_agent_version: "8.13.0"
fleet_server_url: "http://{{ hostvars[groups['ops'][0]]['ansible_host'] }}:8220"
vault_addr: "http://{{ hostvars[groups['ops'][0]]['ansible_host'] }}:8200"
vault_fleet_token_path: "secret/data/elk/fleet-enrollment-token"
```

#### `tasks/main.yml` (séquence)

```yaml
# 1. Lire le root token Vault depuis ops-vm
- name: Slurp vault-init.json from ops-vm
  slurp:
    src: /root/vault-init.json
  become: true
  delegate_to: "{{ groups['ops'][0] }}"
  register: vault_init_raw

- name: Set vault root token fact
  set_fact:
    vault_root_token: "{{ (vault_init_raw.content | b64decode | from_json).root_token }}"

# 2. Lire l'enrollment token depuis Vault
- name: Read Fleet enrollment token from Vault
  uri:
    url: "{{ vault_addr }}/v1/{{ vault_fleet_token_path }}"
    method: GET
    headers:
      X-Vault-Token: "{{ vault_root_token }}"
    status_code: 200
  register: fleet_token_resp
  delegate_to: "{{ groups['ops'][0] }}"

- name: Set enrollment token fact
  set_fact:
    elastic_agent_enrollment_token: "{{ fleet_token_resp.json.data.data.value }}"

# 3. Installer Elastic Agent via apt
- name: Add Elastic GPG key
  ...  (même pattern que filebeat)

- name: Install elastic-agent
  apt:
    name: "elastic-agent={{ elastic_agent_version }}"
    state: present

# 4. Enrôler l'agent dans Fleet
- name: Enroll Elastic Agent
  command: >
    elastic-agent enroll
    --url="{{ fleet_server_url }}"
    --enrollment-token="{{ elastic_agent_enrollment_token }}"
    --insecure
    --non-interactive
  register: enroll_result
  changed_when: "'successfully enrolled' in enroll_result.stdout"

# 5. Démarrer le service
- name: Enable and start elastic-agent
  systemd:
    name: elastic-agent
    state: started
    enabled: true
```

---

### MODIFIÉ — `ansible/roles/elk/tasks/main.yml`

Ajouter à la **fin** du fichier (après `Wait for Elasticsearch`) les tâches Fleet :

```yaml
# --- Fleet Server ---

- name: Create Fleet Server directory
  file:
    path: "{{ elk_dir }}/fleet-server"
    state: directory
    mode: "0755"

- name: Deploy docker-compose.yml (avec fleet-server)
  # (template mis à jour — voir ci-dessous)

- name: Wait for Fleet Server to be ready
  uri:
    url: "http://127.0.0.1:{{ elk_fleet_port }}/api/status"
    method: GET
    status_code: 200
  register: fleet_health
  retries: 20
  delay: 10
  until: fleet_health.status == 200

- name: Get Fleet enrollment token via Kibana API
  uri:
    url: "http://127.0.0.1:{{ elk_kibana_port }}/api/fleet/enrollment_api_keys"
    method: GET
    headers:
      kbn-xsrf: "true"
    status_code: 200
  register: fleet_keys_resp
  retries: 10
  delay: 10
  until: fleet_keys_resp.status == 200 and fleet_keys_resp.json.items | length > 0

- name: Set enrollment token fact
  set_fact:
    fleet_enrollment_token: "{{ fleet_keys_resp.json.items[0].api_key }}"

# --- Écriture dans Vault ---

- name: Read Vault root token
  slurp:
    src: /root/vault-init.json
  become: true
  register: vault_init_raw

- name: Set vault root token
  set_fact:
    vault_root_token: "{{ (vault_init_raw.content | b64decode | from_json).root_token }}"

- name: Enable KV secrets engine in Vault (idempotent)
  uri:
    url: "http://127.0.0.1:8200/v1/sys/mounts/secret"
    method: POST
    headers:
      X-Vault-Token: "{{ vault_root_token }}"
    body_format: json
    body:
      type: kv
      options:
        version: "2"
    status_code: [200, 204, 400]  # 400 = déjà monté, ok

- name: Store Fleet enrollment token in Vault
  uri:
    url: "http://127.0.0.1:8200/v1/secret/data/elk/fleet-enrollment-token"
    method: POST
    headers:
      X-Vault-Token: "{{ vault_root_token }}"
    body_format: json
    body:
      data:
        value: "{{ fleet_enrollment_token }}"
    status_code: [200, 204]

- name: Allow Fleet Server port (UFW)
  ufw:
    rule: allow
    port: "{{ elk_fleet_port | string }}"
    proto: tcp
```

---

### MODIFIÉ — `ansible/roles/elk/defaults/main.yml`

Ajouter la variable Fleet :

```yaml
elk_fleet_port: 8220
```

---

### MODIFIÉ — `ansible/roles/elk/templates/docker-compose.yml.j2`

Ajouter le service `fleet-server` dans le Compose (après kibana) :

```yaml
  fleet-server:
    image: docker.elastic.co/beats/elastic-agent:{{ elk_version }}
    container_name: fleet-server
    environment:
      - FLEET_SERVER_ENABLE=1
      - FLEET_SERVER_ELASTICSEARCH_HOST=http://elasticsearch:9200
      - FLEET_SERVER_ELASTICSEARCH_INSECURE=1
      - FLEET_SERVER_INSECURE_HTTP=1
      - FLEET_URL=http://fleet-server:8220
      - KIBANA_FLEET_HOST=http://kibana:5601
      - KIBANA_FLEET_SETUP=1
    ports:
      - "{{ elk_fleet_port }}:8220"
    networks:
      - elk-net
    depends_on:
      elasticsearch:
        condition: service_healthy
      kibana:
        condition: service_started
    restart: unless-stopped
    user: root
```

---

### NOUVEAU — `ansible/playbooks/elastic-agent.yml`

```yaml
- name: Gather ops-vm facts
  hosts: ops
  gather_facts: true

- name: Deploy Elastic Agent
  hosts: ops:services
  become: true
  roles:
    - elastic-agent
```

Note : le rôle tourne sur **ops et services**. La lecture du vault-init.json est déléguée à ops via `delegate_to`.

---

### SUPPRIMÉ — `ansible/playbooks/filebeat.yml`

Ce playbook est remplacé par `elastic-agent.yml`. À supprimer une fois le rôle `elastic-agent` validé.

Le rôle `filebeat` peut être conservé dans `roles/` pour référence mais ne sera plus appelé.

---

### MODIFIÉ — `scripts/deploy.sh`

Remplacer :
```bash
ansible-playbook playbooks/filebeat.yml -i inventory/onprem.py
```
Par :
```bash
ansible-playbook playbooks/elastic-agent.yml -i inventory/onprem.py
```

---

### MODIFIÉ — `package.json`

```json
"ansible:elastic-agent": "cd ansible && ansible-playbook playbooks/elastic-agent.yml",
"ansible:all": "npm run ansible:vault && npm run ansible:elk && npm run ansible:elastic-agent",
```

Supprimer `ansible:filebeat`.

---

### MODIFIÉ — `.github/workflows/deploy-onprem.yml`

Remplacer l'étape `Deploy Filebeat` par :

```yaml
- name: Deploy Elastic Agents
  run: ansible-playbook playbooks/elastic-agent.yml -i inventory/onprem.py
  working-directory: ansible
  env:
    ANSIBLE_PRIVATE_KEY_FILE: ${{ secrets.ANSIBLE_SSH_PRIVATE_KEY_PATH }}
    OPS_IP: ${{ needs.terraform.outputs.ops_ip }}
```

---

## Dépendances Ansible à ajouter — `ansible/requirements.yml`

```yaml
- name: community.hashi_vault
  version: ">=6.0.0"
```

(Optionnel — on peut faire sans en utilisant le module `uri` directement, ce qui est l'approche retenue dans ce plan pour éviter une dépendance supplémentaire.)

---

## Variables config.env — aucun changement requis

Les variables `VM_ID_OPS`, `VM_IP_OPS` etc. sont déjà correctes. Aucune nouvelle variable n'est nécessaire dans config.env — le token circule uniquement via Vault et les facts Ansible en mémoire.

---

## Séquence de validation post-déploiement

```bash
# 1. Vérifier que Fleet Server tourne
ssh -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.242 \
  "docker compose -f /opt/elk/docker-compose.yml ps fleet-server"

# 2. Vérifier que le token est bien dans Vault
ssh -o ProxyJump=root@51.75.128.134 ubuntu@172.16.0.242 \
  "docker exec vault vault kv get -address=http://127.0.0.1:8200 secret/elk/fleet-enrollment-token"

# 3. Vérifier les agents enrôlés dans Fleet (Kibana)
# Tunnel SSH : ssh -N -L 5601:172.16.0.242:5601 ...
# → http://localhost:5601 → Fleet → Agents
# Les deux agents (ops-vm + services-vm) doivent apparaître "Healthy"

# 4. Vérifier les données dans Elasticsearch
curl -s http://localhost:9200/_cat/indices?v | grep -E "metrics|logs"
```

---

## Pièges connus

| Piège | Détail | Fix |
|---|---|---|
| Fleet setup Kibana non prêt | Kibana peut prendre 60-90s à être fully ready après le healthcheck ES | Augmenter le retries/delay sur l'attente Fleet |
| Enrollment token vide | `fleet/enrollment_api_keys` retourne liste vide si Fleet n'a pas fini son setup | Attendre que Kibana Fleet soit initialized (`GET /api/fleet/setup` retourne `isInitialized: true`) |
| `elastic-agent enroll` non idempotent | Si relancé, l'agent tente de re-enrôler et échoue | Vérifier `elastic-agent status` avant d'enrôler, skip si déjà enrolled |
| Vault non unsealed | Si ops-vm a redémarré, Vault est sealed → le rôle elastic-agent ne peut pas lire le token | Ajouter une tâche de vérification du statut Vault en début du rôle elk |
| KV engine déjà monté | `POST /v1/sys/mounts/secret` retourne 400 si déjà présent | `status_code: [200, 204, 400]` — déjà géré dans le plan |
| `--insecure` sur l'enrollment | Requis car Fleet Server tourne sans TLS | Flag `--insecure` dans la commande `elastic-agent enroll` |

---

## État actuel de l'infra (référence rapide)

| Élément | Valeur |
|---|---|
| Branche courante | `adding-stack-ELK` |
| ops-vm IP (DHCP) | `172.16.0.242` |
| services-vm IP (DHCP) | `172.16.0.241` |
| Proxmox host | `51.75.128.134` |
| ELK version | `8.13.0` |
| Vault version | `latest` (hashicorp/vault) |
| Vault init file | `/root/vault-init.json` sur ops-vm |
| ELK Compose dir | `/opt/elk/` sur ops-vm |
| xpack.security | `disabled` |
| Groupe Ansible ops | `ops` → host `ops-vm` |
| Groupe Ansible services | `services` → host `services-vm` |
| Inventaire | `ansible/inventory/onprem.py` (dynamique, lit config.env) |
| Variable env OPS IP | `OPS_IP` (exportée par deploy.sh) |

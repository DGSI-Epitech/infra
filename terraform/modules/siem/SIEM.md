# ELK Stack — Configuration Ansible

Stack SIEM déployée sur `ops-vm` (VM 120, 8 Go RAM) via Docker Compose.

Pour la création de la VM, voir le module Terraform `ops-vm`.

---

## Composants

| Service | Version | Port | Mémoire |
|---|---|---|---|
| Elasticsearch | 8.13.0 | 9200 (API), 9300 (cluster) | 2 Go (heap 1 Go) |
| Logstash | 8.13.0 | 5044 (Beats input) | 1,2 Go (heap 512 Mo) |
| Kibana | 8.13.0 | 5601 | 1 Go |
| Fleet Server | 8.13.0 | 8220 | 1 Go |

Répertoire de base : `/opt/elk/`

---

## Déploiement

```bash
cd ansible
ansible-playbook -i inventory/onprem.py playbooks/elk.yml
```

Le rôle `elk` :
1. Démarre Elasticsearch seul → attend le health check
2. Configure le mot de passe `kibana_system`
3. Crée le service token Fleet Server via l'API ES
4. Redéploie `docker-compose.yml` avec le token
5. Démarre Logstash + Kibana → attend Kibana `/api/status`
6. `POST /api/fleet/setup` (initialisation Fleet)
7. Crée la "Default policy" (agents réguliers) + intégration `system`
8. Configure l'URL Fleet Server dans Kibana
9. Crée la "Default Fleet Server Policy" + intégration `fleet_server`
10. Démarre fleet-server → attend status HEALTHY
11. Récupère l'enrollment token (hors Fleet Server policy)
12. Stocke le token dans Vault (`secret/data/elk/fleet-enrollment-token`)

---

## Variables (ansible/roles/elk/defaults/main.yml)

| Variable | Valeur par défaut | Description |
|---|---|---|
| `elk_version` | `8.13.0` | Version de toute la stack |
| `elk_dir` | `/opt/elk` | Répertoire Docker Compose |
| `elk_elastic_password` | `changeme` | Mot de passe user `elastic` |
| `elk_kibana_system_password` | `changeme` | Mot de passe `kibana_system` |
| `elk_es_heap_size` | `1g` | Heap JVM Elasticsearch |
| `elk_ls_heap_size` | `512m` | Heap JVM Logstash |

> Surcharger ces variables via `ansible/playbooks/elk.yml` ou un fichier `vars/`.

---

## Accès à Kibana

Kibana tourne sur `ops-vm` (réseau privé `vmbr1`). Ouvrir un tunnel SSH :

```bash
ssh -L 5601:OPS_IP:5601 -N root@51.75.128.134
```

Puis ouvrir dans le navigateur : `http://localhost:5601`

Login : `elastic` / valeur de `elk_elastic_password`

Pour accéder à Fleet et Elasticsearch en même temps :

```bash
ssh -L 5601:OPS_IP:5601 \
    -L 9200:OPS_IP:9200 \
    -L 8220:OPS_IP:8220 \
    -N root@51.75.128.134
```

> Remplacer `OPS_IP` par l'IP courante de ops-vm (lire via `deploy.sh` ou QEMU agent).

---

## Elastic Agent — enrollment

Le rôle `elastic-agent` récupère le token depuis Vault et enrôle l'agent auprès de Fleet Server.

Playbook cible : `ops` + `services` :

```bash
ansible-playbook -i inventory/onprem.py playbooks/elastic-agent.yml
```

---

## Pièges connus

| Problème | Cause | Fix |
|---|---|---|
| OOM fleet-server / Kibana | Pas de `mem_limit` sur Docker | Limits imposées : ES 2g, LS 1200m, Kibana 1g, Fleet 1g |
| Fleet Server "waiting on default policy" | `POST /api/fleet/setup` ne crée pas la Fleet Server policy | Créer manuellement via API (déjà géré dans le rôle) |
| Enrollment token = token Fleet Server | `items[0]` est le token FS, pas les agents | Filtre `rejectattr('policy_id', ...)` dans le rôle |
| `elastic-agent enroll` socket absent | Daemon pas encore démarré | `systemctl start elastic-agent` avant `enroll` |
| Clé GPG apt format armored | `get_url` sauvegarde en ASCII | `curl \| gpg --dearmor -o ...` dans le rôle |

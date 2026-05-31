# Architecture

Infrastructure as Code pour un lab école déployé sur deux sites Proxmox.

---

## Vue d'ensemble

```
Internet
   │
   ├── SSH direct ──────────────────────────────────────────────────────────┐
   │                                                                        │
   ▼                                                                        ▼
pfSense-OP (PVE1)                                              pfSense-Cloud (PVE2)
5.196.45.8                                                     5.196.50.52
LAN: 172.16.0.240/28                                         DMZ: 10.255.255.248/29
   │                                                           LAN: 192.168.255.240/28
   │  OpenVPN 10.3.3.0/29                                         │
   └──────────────────────────────────────────────────────────────┘
   │                                                           │
   ├── 172.16.0.253  ops-vm                                  ├── 10.255.255.253  bastion
   │    Elasticsearch :9200                                    │    Kibana         :5601
   │    Vault         :8200                                    │    Filebeat
   │    Filebeat                                               │
   │                                                           └── 192.168.255.253  web
   └── 172.16.0.241  services-vm (⚠️ hors ligne)                 Site web
```

---

## Sites Proxmox

### PVE1 — On-Premise (`ns3050272.ip-51-255-76.eu`, nœud `vm3`)

| VMID | VM | IP | Services |
|------|----|----|----------|
| 125 | pfSense-OP | WAN: 5.196.45.8 / LAN: 172.16.0.254 | Firewall, VPN, DNS |
| 2038 | ops-vm | 172.16.0.253/28 | Elasticsearch, Vault, Filebeat |
| 3038 | services-vm | 172.16.0.241/28 | ⚠️ hors ligne |

### PVE2 — Cloud (`ns3183326.ip-146-59-253.eu`, nœud `vm002`)

| VMID | VM | IP | Services |
|------|----|----|----------|
| 106 | pfSense-Cloud | WAN: 5.196.50.52 | Firewall, VPN |
| 2038 | bastion | 10.255.255.253/29 (DMZ) | Kibana, Filebeat |
| 3038 | web | 192.168.255.253/28 (LAN) | Site web |

---

## Accès SSH

Toutes les VMs sont sur des réseaux privés. L'accès passe par un ProxyJump pfSense :

```
# PVE1 (ops-vm, services-vm)
ssh -J admin@5.196.45.8 dgsi-op@172.16.0.253

# PVE2 (bastion, web)
ssh -J admin@5.196.50.52 dgsi-cloud@10.255.255.253
```

Ansible utilise le script dynamique `inventory/onprem.py` qui configure automatiquement le ProxyJump depuis `config.env`.

---

## TLS / PKI interne

Une CA interne (DGSI Internal CA) gère les certificats de tous les services.

| Composant | Localisation |
|-----------|-------------|
| CA privkey | `~/.ansible-tls/ca.key` (hors repo, sur le controller) |
| CA cert | `~/.ansible-tls/ca.crt` |
| Certs par host | `~/.ansible-tls/<hostname>/` |
| Déploiement | `/etc/ssl/internal/` sur chaque VM |

Rôle Ansible : `roles/tls/` — génère sur localhost, déploie sur les hosts cibles.
Playbook : `playbooks/tls.yml` → cible `ops:bastion`.

---

## Services

### ops-vm (172.16.0.253)

| Service | Container | Port | TLS |
|---------|-----------|------|-----|
| Elasticsearch | `elasticsearch` (Docker Compose) | 9200 (API), 9300 (cluster) | HTTPS ✅ |
| Vault | `vault` (Docker standalone) | 8200 | HTTPS ✅ |
| Filebeat | systemd service | — | Envoie vers ES en HTTPS |

Docker Compose file : `/opt/elk/docker-compose.yml`
Config ES : `/opt/elk/elasticsearch/config/elasticsearch.yml`
Certs : `/etc/ssl/internal/` monté en lecture seule dans les containers

### bastion (10.255.255.253)

| Service | Container | Port | TLS |
|---------|-----------|------|-----|
| Kibana | `kibana` (Docker Compose) | 5601 | HTTPS ✅ |
| Filebeat | systemd service | — | Envoie vers ES en HTTPS |

Kibana se connecte à Elasticsearch via HTTPS sur 172.16.0.253:9200 (via tunnel VPN).

### web (192.168.255.253)

Site web uniquement. Pas de Docker installé.

---

## Flux de logs

```
ops-vm   ─── Filebeat ──────────────────────────────────────────┐
bastion  ─── Filebeat ──────────────────────────────────────────┤
                                                                 │ HTTPS:9200
                                                                 ▼
                                                       Elasticsearch (ops-vm)
                                                                 │
                                                                 ▼
                                                       Kibana (bastion) :5601
                                                       index: filebeat-8.x-*
                                                       ILM: rollover 1GB/7j, delete 30j
```

---

## Gestion du disque

Toutes les VMs ont un disque de **7.6G**. Contrainte structurelle : les images Docker lourdes laissent peu de marge.

| VM | Disk% | Images Docker | Marge |
|----|-------|--------------|-------|
| ops-vm | ~87% | ES 1.88GB + Vault 612MB | ~900MB |
| bastion | ~73% | Kibana 1.73GB | ~2GB |
| web | ~63% | aucune | ~2.7GB |

Mesures en place :
- ILM Elasticsearch : rollover 1GB/7j, delete après 30 jours
- Docker log rotation : 10MB/3 fichiers max (configuré dans `/etc/docker/daemon.json`)
- Journal systemd : vacuum à 100MB (via rôle `base`)
- Cache apt : nettoyage à chaque run du rôle `base`

---

## Ansible — Rôles

| Rôle | Playbook | Cible | Description |
|------|----------|-------|-------------|
| `tls` | `tls.yml` | ops, bastion | CA interne + certs signés |
| `base` | (inclus) | toutes VMs | Docker, UFW, SSH, rotation logs |
| `vault` | `vault.yml` | ops | HashiCorp Vault en Docker |
| `elk` | `elk.yml` | ops | Elasticsearch seul (Docker Compose) |
| `kibana` | `kibana.yml` | bastion | Kibana standalone (Docker Compose) |
| `filebeat` | `filebeat.yml` | ops, bastion | Filebeat → Elasticsearch HTTPS |
| `pfsense` | `pfsense.yml` | pfsense-op, pfsense-cloud | Firewall, VPN, DNS |

Ordre de déploiement :
1. `tls.yml` — certs avant tout
2. `vault.yml`
3. `elk.yml`
4. `kibana.yml`
5. `filebeat.yml`

---

## Décisions techniques récentes

| Décision | Raison |
|----------|--------|
| Kibana séparé du Compose ELK | ops-vm à 90% disk — Kibana (1.73GB) déplacé sur bastion |
| Filebeat direct → ES (sans Logstash) | Logstash inutile pour du log forwarding simple ; réduit les images Docker |
| TLS interne via CA Ansible | Pas de domaine public → Let's Encrypt impossible ; CA interne via `community.crypto` |
| ProxyJump via pfSense (pas Proxmox) | Proxmox école : pas d'accès SSH root sur les nœuds PVE |
| ILM Elasticsearch | Prévenir la croissance non contrôlée de l'index sur 7.6G |
| daemon.json centralisé dans `base` | DNS + log rotation dans un seul endroit — évite les conflits entre rôles |

# Plan de Tests — Validation End-to-End des Services

## Scope

Validation complète des services applicatifs (**NetBox**, **ELK**, **Kibana**, **Vault**, **Website**), du pipeline de logs et de l’exposition réseau.

---

# 1. NetBox — Accuracy & Auto-Update

## Objectif

Vérifier que NetBox reflète correctement l’état réel de l’infrastructure et que les mises à jour sont automatiques.

### Test 1.1 : Vérification des IPs des VMs

#### Action

```bash
# Vérifier IP ops-vm
ssh -J root@51.75.128.134 ubuntu@172.16.0.242 ip a

# Vérifier IP bastion
ssh -J root@51.75.128.134 ubuntu@10.255.255.249 ip a

# Vérifier IP website
ssh -J root@51.75.128.134 ubuntu@192.168.255.243 ip a
```

#### Attendu

- ops-vm : `172.16.0.x`
- bastion : `10.255.255.249`
- website : `192.168.255.243`
- Correspondance exacte dans NetBox

---

### Test 1.2 : Auto-update DHCP

#### Action

```bash
# Reboot services-vm
ssh -J root@51.75.128.134 ubuntu@172.16.0.241 sudo reboot
```

Attendre puis re-vérifier l’adresse IP via QEMU Agent ou SSH.

#### Attendu

- Nouvelle IP détectée
- NetBox mis à jour automatiquement

---

### Résultats attendus

- [ ] Données cohérentes avec l’infrastructure réelle
- [ ] Auto-update fonctionnel

---

# 2. Pipeline Logs — Filebeat → Elasticsearch

## Objectif

Valider que les logs sont envoyés, reçus et stockés correctement.

### Test 2.1 : Filebeat actif

#### Action

```bash
ansible ops:bastion -m shell -a "systemctl is-active filebeat"
```

#### Attendu

```text
active
```

---

### Test 2.2 : Injection de log

#### Action

```bash
ssh -J admin@192.168.255.254 ubuntu@172.16.0.242 "logger TEST_E2E_LOG"
```

---

### Test 2.3 : Vérifier la réception dans Elasticsearch

#### Action

```bash
curl -sk \
  --cacert ~/.ansible-tls/ca.crt \
  -u elastic:changeme \
  "https://localhost:9200/_search?q=TEST_E2E_LOG&pretty"
```

#### Attendu

- Log trouvé dans Elasticsearch

---

### Test 2.4 : Vérification des indices

#### Action

```bash
curl -sk \
  --cacert ~/.ansible-tls/ca.crt \
  -u elastic:changeme \
  "https://localhost:9200/_cat/indices?v"
```

#### Attendu

- Présence d’indices `.ds-filebeat-*`
- `docs.count > 0`

---

### Résultats attendus

- [ ] Logs envoyés
- [ ] Logs reçus
- [ ] Index générés

---

# 3. Kibana — Visualisation des Données

## Objectif

Vérifier que les dashboards affichent des données réelles.

### Test 3.1 : Accès Kibana

#### Action

```bash
curl -sk https://localhost:5601
```

#### Attendu

- Réponse HTML Kibana

---

### Test 3.2 : Données visibles

#### Action

Dans **Kibana > Discover** :

```text
TEST_E2E_LOG
```

#### Attendu

- Log visible dans les résultats

---

### Test 3.3 : Données temps réel

#### Action

```bash
logger LIVE_TEST
```

#### Attendu

- Apparition quasi immédiate dans Kibana

---

### Résultats attendus

- [ ] Interface accessible
- [ ] Données présentes
- [ ] Temps réel fonctionnel

---

# 4. Website — Access Control

## Objectif

Vérifier que le site est accessible en interne mais bloqué depuis l’extérieur.

### Test 4.1 : Accès depuis le bastion

#### Action

```bash
ssh -J root@51.75.128.134 ubuntu@10.255.255.249

curl http://192.168.255.243
```

#### Attendu

```text
HTTP 200
```

---

### Test 4.2 : Accès inter-site (VPN)

#### Action

```bash
ssh -J admin@192.168.255.254 ubuntu@172.16.0.242

curl http://192.168.255.243
```

#### Attendu

```text
HTTP 200
```

---

### Test 4.3 : Accès externe (sécurité)

#### Action

```bash
curl http://192.168.255.254
```

ou

```bash
nmap -p 80,443 192.168.255.254
```

#### Attendu

- Ports fermés (`closed`)
- ou filtrés (`filtered`)

---

### Résultats attendus

- [ ] Accessible en interne
- [ ] Accessible via VPN
- [ ] Bloqué depuis l’extérieur

---

# 5. Vault — Disponibilité & État

## Objectif

Vérifier que Vault est opérationnel et déverrouillé.

### Test 5.1 : Health Check

#### Action

```bash
curl -sk \
  --cacert ~/.ansible-tls/ca.crt \
  https://localhost:8200/v1/sys/health \
  | python3 -m json.tool
```

#### Attendu

```json
{
  "initialized": true,
  "sealed": false
}
```

---

### Résultats attendus

- [ ] Vault initialisé
- [ ] Vault unsealed

---

# 6. Elasticsearch — Santé du Cluster

## Objectif

Vérifier le bon fonctionnement du cluster Elasticsearch.

### Test 6.1 : Cluster Health

#### Action

```bash
curl -sk \
  --cacert ~/.ansible-tls/ca.crt \
  -u elastic:changeme \
  "https://localhost:9200/_cluster/health?pretty"
```

#### Attendu

```json
{
  "status": "yellow"
}
```

ou

```json
{
  "status": "green"
}
```

---

### Résultats attendus

- [ ] Cluster opérationnel

---

# 7. Documentation des Issues

## Format

```markdown
### Issue #<N> : <Titre>

**Sévérité** : Critical | High | Medium | Low

**Composant** :
[ELK | NetBox | Vault | Website | Network]

**Description** :
...

**Impact** :
...

**Correctif** :
...

**Validation** :

```bash
# commande de validation
```

**Status** :
- [ ] Open
- [x] Fixed
```

---

# Exécution Globale

## Phase 1 — Connectivité

- [ ] Tunnels SSH
- [ ] Accès aux services

## Phase 2 — Inventaire & Logs

- [ ] NetBox
- [ ] Pipeline de logs

## Phase 3 — Visualisation & Website

- [ ] Kibana
- [ ] Website

## Phase 4 — Services Critiques

- [ ] Vault
- [ ] Elasticsearch

## Phase 5 — Clôture

- [ ] Documentation des issues
- [ ] Validation finale
- [ ] Rapport de recette
# Plan de tests réseau et sécurité

Scope : Tests de connectivité VPN, sécurité firewall, accès Teleport, DNS cross-site

---

## 1. VPN Connectivity S1 ↔ S2

### Objectif
Vérifier que les deux sites (PVE1 @ 51.75.128.134 et PVE2 @ 51.75.128.134) peuvent communiquer via le tunnel VPN sur les interfaces de gestion interne.

### Ressources
- pfSense-OP : 192.168.255.254 (Site 1 / PVE1)
- pfSense-Cloud : 192.168.255.254 (Site 2 / PVE2)
- VPN interface : IPsec tunnel (à vérifier dans pfSense UI)

### Test 1.1 : Ping ops-vm depuis web-vm
```bash
# SSH via ProxyJump vers ops-vm (172.16.0.253)
ssh -J admin@192.168.255.254 ubuntu@172.16.0.253

# Depuis ops-vm, ping web-vm sur le LAN PVE2 (192.168.255.243)
ping -c 4 192.168.255.243
# Attendu : 4 paquets reçus, 0% de perte
```

### Test 1.2 : Ping services-vm depuis bastion
```bash
# SSH vers bastion (10.255.255.249) — DMZ PVE2
ssh -J admin@192.168.255.254 ubuntu@10.255.255.249

# Depuis bastion, ping services-vm (172.16.0.241) sur DMZ PVE1
ping -c 4 172.16.0.241
# Attendu : 4 paquets reçus, 0% de perte
```

### Test 1.3 : Vérifier les routes VPN actives sur pfSense-OP
```bash
ssh admin@192.168.255.254

# Vérifier IPsec peer status
# Menu : Status > IPsec > ESP Connections
# Attendu : tunnel actif, phase 1 & 2 établies

# Ou via SSH :
# Remplacer par l'équivalent CLI pfSense (ipsecctl -sa)
```

### Résultats attendus
- [ ] Ping ops-vm → web-vm : succès (0% perte)
- [ ] Ping bastion → services-vm : succès (0% perte)
- [ ] IPsec tunnel : actif sur les deux pfSense
- [ ] Latence : < 50ms (géographiquement proche sur 51.75.128.134)

### Problèmes potentiels & Mitigation
| Problème | Cause | Solution |
|----------|-------|----------|
| Perte de paquets VPN | Tunnel flappant | Vérifier Phase 1/2 sur pfSense, logs `/var/log/ipsec.log` |
| Impossible joindre services-vm | VM off-line (cf. services-state.md) | Démarrer services-vm via Proxmox UI |
| Firewall bloque le tunnel | Règles WAN pfSense | Vérifier firewall rules sur WAN inbound (UDP 500, 4500) |

---

## 2. Kill Switch Activation / Deactivation / Recovery

### Objectif
Tester le mécanisme d'arrêt d'urgence du VPN (kill switch) : vérifier que couper le tunnel VPN coupe la communication inter-site et que la réactivation rétablit la connexion.

### Test 2.1 : Baseline (communication OK)
```bash
ssh -J admin@192.168.255.254 ubuntu@172.16.0.253
ping -c 10 192.168.255.243 > /tmp/baseline.txt
# Attendu : 100% succès (tous les paquets arrivent)
```

### Test 2.2 : Kill switch activation (pfSense UI)
```bash
# SSH vers pfSense-OP
ssh admin@192.168.255.254

# Menu Status > IPsec > désactiver le tunnel (ou utiliser l'API)
# Alternativement : via SSH
# ipsecctl -D  (tout couper)
```

### Test 2.3 : Vérifier la perte de connexion
```bash
# Depuis une autre session, tester la perte imédiate
ssh -J admin@192.168.255.254 ubuntu@172.16.0.253
ping -c 10 192.168.255.243
# Attendu : timeout ou 100% de perte
```

### Test 2.4 : Recovery (réactiver le tunnel)
```bash
# SSH vers pfSense-OP
ssh admin@192.168.255.254

# Réactiver le tunnel (Menu Status > IPsec > enable)
# Ou via CLI : ipsecctl -f

# Vérifier la reconnexion
sleep 5  # Laisser le tunnel se rétablir
```

### Test 2.5 : Vérifier le rétablissement
```bash
# Depuis ops-vm, re-tester la connexion
ssh -J admin@192.168.255.254 ubuntu@172.16.0.253
ping -c 10 192.168.255.243
# Attendu : 100% succès (connexion rétablie)
```

### Résultats attendus
- [ ] Baseline : 100% succès avant kill switch
- [ ] Kill switch : 100% perte de paquets après désactivation
- [ ] Recovery : 100% succès après réactivation
- [ ] Temps de rétablissement : < 10 secondes après réactivation

---

## 3. Teleport Access (SSH + Web Console)

### Objectif
Vérifier que Teleport (access plane) permet de se connecter en SSH et d'accéder aux web consoles des services (Kibana, Vault, etc.).

### Ressources
- Teleport server : aucun déploiement actuellement (à vérifier)
- Services web : Kibana (bastion :5601), Vault (ops-vm :8200)

### Test 3.1 : Vérifier Teleport est installé/running
```bash
# Sur bastion (accès Teleport probable)
ssh -J admin@192.168.255.254 ubuntu@10.255.255.249

# Vérifier si Teleport daemon tourne
systemctl status teleport
# ou
ps aux | grep teleport

# Récupérer le status
tctl status
```

### Test 3.2 : SSH via Teleport proxy
```bash
# Si Teleport est déployé, utiliser tsh (Teleport client)
tsh login --proxy=10.255.255.249:3080

# Lister les nodes disponibles
tsh ls

# Se connecter à un node via Teleport
tsh ssh ubuntu@ops-vm
```

### Test 3.3 : Web console access (Teleport web UI)
```bash
# Accédez à https://<teleport-proxy>:3080/web
# Attendu : authentification réussie, accès aux web apps enregistrées

# Via tunnel SSH si Teleport n'est pas public
ssh -J admin@192.168.255.254 -L 3080:10.255.255.249:3080 ubuntu@10.255.255.249

# Puis visitez https://localhost:3080
```

### Test 3.4 : Accès aux web consoles (Kibana, Vault)
```bash
# Si Teleport n'est pas disponible, utiliser SSH tunneling direct

# Kibana (bastion :5601)
ssh -J admin@192.168.255.254 -L 5601:10.255.255.249:5601 ubuntu@10.255.255.249
# Puis : https://localhost:5601

# Vault (ops-vm :8200)
ssh -J admin@192.168.255.254 -L 8200:172.16.0.253:8200 ubuntu@172.16.0.253
# Puis : https://localhost:8200
```

### Résultats attendus
- [ ] Teleport daemon : running ou déploiement confirmé nécessaire
- [ ] SSH via Teleport : succès ou alternative (tunnel SSH direct)
- [ ] Web console Kibana : accessible en HTTPS (cert CA interne)
- [ ] Web console Vault : accessible en HTTPS (cert CA interne)
- [ ] Authentification : MFA requise (vérifier setup Teleport)

### Issues à documenter
- [ ] Teleport pas en place ? → Déploiement requis (PR ou task future)
- [ ] Certificats CA interne : acceptés ou warning navigateur ?

---

## 4. DNS Resolution Cross-Site

### Objectif
Vérifier que la résolution DNS fonctionne correctement entre les deux sites via les serveurs DNS configurés (pfSense) et que les enregistrements intra-site et inter-site se résolvent correctement.

### Ressources
- DNS primaire : pfSense-OP (192.168.255.254) avec resolver local
- DNS secondaire : pfSense-Cloud (192.168.255.254)
- Records : à définir dans pfSense ou Unbound

### Test 4.1 : DNS resolution depuis ops-vm (S1 interne)
```bash
ssh -J admin@192.168.255.254 ubuntu@172.16.0.253

# Test résolution locale (interne S1)
nslookup vault.internal      # Attendu : 172.16.0.253 (ops-vm)
nslookup elasticsearch.internal  # Attendu : 172.16.0.253 (ops-vm)

# Test résolution inter-site
nslookup web.internal        # Attendu : 192.168.255.243 (web-vm S2)
```

### Test 4.2 : DNS resolution depuis bastion (S2 DMZ)
```bash
ssh -J admin@192.168.255.254 ubuntu@10.255.255.249

# Test résolution locale (interne S2)
nslookup kibana.internal     # Attendu : 10.255.255.249 (bastion)

# Test résolution inter-site
nslookup vault.internal      # Attendu : 172.16.0.253 (ops-vm S1)
nslookup elasticsearch.internal  # Attendu : 172.16.0.253
```

### Test 4.3 : Vérifier les nameservers
```bash
# Sur chaque VM, vérifier le nameserver configuré
cat /etc/resolv.conf
# Attendu : nameserver 172.16.0.1 (pfSense-OP) ou 10.255.255.1 (pfSense-Cloud)

# Ou si systemd-resolved
resolvectl status
# Attendu : DNS servers pointant vers pfSense
```

### Test 4.4 : Vérifier les records sur pfSense
```bash
ssh admin@192.168.255.254

# Accédez à Services > DNS > Resolver (Unbound)
# Vérifier les forward zones (split-DNS pour domaines inter-site)
# Ou via API/CLI pfSense (si disponible)

# Records attendus :
# vault.internal → 172.16.0.253
# elasticsearch.internal → 172.16.0.253
# kibana.internal → 10.255.255.249
# web.internal → 192.168.255.243
# services-vm.internal → 172.16.0.241
```

### Résultats attendus
- [ ] DNS résolution locale : succès (vault, elasticsearch depuis S1)
- [ ] DNS résolution inter-site : succès (web-vm visible depuis S1)
- [ ] Nameservers : pfSense correctement configurés
- [ ] Latence DNS : < 10ms (réseau interne)

### Issues à documenter
- [ ] DNS timeout sur un domaine spécifique ? → Vérifier records pfSense
- [ ] NXDOMAIN retourné ? → Enregistrement absent, ajouter dans Unbound

---

## 5. Firewall: Verify Blocked Ports (nmap scan)

### Objectif
Vérifier que les ports non-autorisés sont effectivement bloqués par les règles firewall pfSense et que les ports ouverts sont accessibles.

### Ressources
- nmap : à installer sur le test host
- Ports à scanner : TCP 80, 443, 22, 8200 (Vault), 9200 (ES), 5601 (Kibana), 5044 (Logstash fermé)

### Test 5.1 : Installer nmap
```bash
# Sur un host avec accès réseau (peut être local ou une VM)
# Windows
choco install nmap

# Linux
sudo apt-get install nmap

# macOS
brew install nmap
```

### Test 5.2 : Scan depuis l'extérieur (WAN) vers pfSense-OP
```bash
# Scanner les ports publics depuis un host externe (ou via simulation)
nmap -p 22,80,443,500,4500 192.168.255.254

# Résultats attendus :
# 22 (SSH) : filtered (bloqué intentionnellement)
# 80 (HTTP) : filtered
# 443 (HTTPS) : open (API ou UI pfSense)
# 500 (IPsec) : open (VPN)
# 4500 (NAT-T) : open (VPN)
```

### Test 5.3 : Scan depuis S1 interne vers S2 (Bastion)
```bash
ssh -J admin@192.168.255.254 ubuntu@172.16.0.253

# Scanner bastion (S2) depuis ops-vm (S1 interne)
nmap -p 22,80,443,5601,8200,9200 10.255.255.249

# Résultats attendus :
# 22 (SSH) : open (accès autorisé S1 → S2)
# 443 (HTTPS) : open
# 5601 (Kibana) : open
# 8200 (Vault) : filtered (sur bastion ?) ou closed
# 9200 (ES) : filtered (ES sur ops-vm, pas bastion)
```

### Test 5.4 : Scan depuis S2 interne vers S1 (ops-vm)
```bash
ssh -J admin@192.168.255.254 ubuntu@10.255.255.249

# Scanner ops-vm (S1) depuis bastion (S2)
nmap -p 22,80,443,8200,9200 172.16.0.253

# Résultats attendus :
# 22 (SSH) : open
# 443 (HTTPS) : open
# 8200 (Vault) : open
# 9200 (ES) : open (HTTPS)
# 5601 (Kibana) : filtered (Kibana sur bastion, pas ops-vm)
```

### Test 5.5 : Vérifier port fermé (Logstash 5044 supprimé)
```bash
# Depuis n'importe quel host interne
nmap -p 5044 172.16.0.253
nmap -p 5044 10.255.255.249

# Résultats attendus : closed ou filtered (indique vraiment pas de listener)
```

### Résultats attendus
- [ ] WAN : ports VPN (500, 4500) open, autres filtered
- [ ] S1→S2 (intra-VPN) : ports services open
- [ ] S2→S1 (intra-VPN) : ports services open
- [ ] Port supprimé (5044) : closed/filtered
- [ ] Latence réseau : OK (< 50ms)

### Firewall rules à documenter
```
WAN inbound (pfSense-OP):
  - Autoriser UDP 500 (IPsec phase 1)
  - Autoriser UDP 4500 (IPsec NAT-T)
  - Bloquer SSH (22) sauf exception
  
LAN inbound (ops-vm, bastion):
  - Autoriser SSH (22) inter-site
  - Autoriser HTTPS (443) inter-site
  - Autoriser 8200 (Vault) inter-site
  - Autoriser 9200 (Elasticsearch) inter-site
  - Autoriser 5601 (Kibana) vers bastion uniquement
```

---

## 6. Document Issues Found

### Format de rapport
Pour chaque issue trouvée, documenter :

```markdown
### Issue #<N> : <titre court>

**Severité** : Critical | High | Medium | Low

**Composant** : [VPN | Firewall | DNS | Teleport | Architecture]

**Description** :
[Décrire le problème observé]

**Impact** :
[Impact sur les opérations]

**Mitigation/Fix** :
[Actions correctives suggérées]

**Test verification** :
```bash
# Commande pour vérifier que le fix fonctionne
```

**Status** : [ ] Open | [x] Fixed | [ ] Blocked
```

### Template issue (à reproduire dans ce fichier en section 6.1, 6.2, etc.)
- Remplir à mesure que les tests révèlent des problèmes
- Lier aux tasks Ansible/Terraform pour fixes
- Mettre à jour ce document après chaque correction

---

## Exécution globale

### Phase 1 : Préparation
1. [ ] Vérifier état des services (cf. services-state.md)
2. [ ] Vérifier connectivité SSH de base
3. [ ] Installer nmap sur le test host
4. [ ] Configurer les tunnels SSH longue durée

### Phase 2 : Tests VPN + Kill Switch
1. [ ] Test 1.1-1.3 : VPN connectivity
2. [ ] Test 2.1-2.5 : Kill switch
3. [ ] Documenter latences et timeouts

### Phase 3 : Tests Accès Teleport + DNS
1. [ ] Test 3.1-3.4 : Teleport access
2. [ ] Test 4.1-4.4 : DNS resolution
3. [ ] Collecter les nameservers et records

### Phase 4 : Tests Sécurité (nmap)
1. [ ] Test 5.1-5.5 : Firewall port scan
2. [ ] Compiler les résultats nmap
3. [ ] Comparer avec les rules pfSense attendues

### Phase 5 : Issues
1. [ ] Documenter tous les problèmes trouvés (section 6)
2. [ ] Classer par severité
3. [ ] Assigner aux tasks de correction

---

## Annexe : Scripts réutilisables

### Script : test_vpn_connectivity.sh
```bash
#!/bin/bash
# Usage : ./test_vpn_connectivity.sh <source_host> <dest_ip> <dest_host_description>

SOURCE=$1
DEST_IP=$2
DESC=$3

echo "=== VPN Connectivity Test ==="
echo "From: $SOURCE"
echo "To: $DEST_IP ($DESC)"
echo ""

ping -c 4 "$DEST_IP"
RESULT=$?

if [ $RESULT -eq 0 ]; then
  echo "✓ SUCCESS: $DESC is reachable"
else
  echo "✗ FAILED: $DESC is unreachable"
fi

exit $RESULT
```

### Script : test_firewall_ports.sh
```bash
#!/bin/bash
# Usage : ./test_firewall_ports.sh <target_host> <port_list>

TARGET=$1
PORTS=${2:-"22,80,443,8200,9200,5601"}

echo "=== Firewall Port Scan ==="
echo "Target: $TARGET"
echo "Ports: $PORTS"
echo ""

nmap -p "$PORTS" "$TARGET"
```

---

## Checklist finale

Avant de fermer ce plan de tests :

- [ ] Tous les tests exécutés et documentés
- [ ] Issues classées et prioritizées
- [ ] Fixes appliqués et re-testés
- [ ] Resultat finaux documentés dans ce fichier (section 6)
- [ ] PR créée et validée

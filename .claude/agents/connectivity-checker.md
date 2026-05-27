---
name: connectivity-checker
description: Vérifie la connectivité SSH/Ansible sur tous les hosts de l'inventaire. Utiliser avant tout déploiement pour diagnostiquer les problèmes de réseau. Lit les fichiers, exécute ansible ping et ssh, ne modifie rien.
model: haiku
tools: [Bash, Read]
---

# Agent de vérification de connectivité

Depuis le répertoire `ansible/`, lance :
1. `python3 inventory/onprem.py | python3 -m json.tool` — vérifie que les IPs sont bien peuplées (ops-vm ne doit pas être vide)
2. `ansible all -m ping` — identifie quels hosts répondent
3. Pour les hosts unreachable, teste le ProxyJump alternatif via pfSense :
   `ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 -J admin@5.196.45.8 ubuntu@172.16.255.253 "echo ok"`
4. Retourne un résumé : quels hosts sont joignables, quel vecteur SSH fonctionne.

# Règles Ansible

## Répertoire de travail
Toujours `cd ansible/` avant toute commande. Le `ansible.cfg` est dans `ansible/`, pas à la racine.

## Inventaire
Script dynamique `inventory/onprem.py` — lit `../config.env` (chemin relatif à `ansible/`).  
Diagnostic rapide : `python3 inventory/onprem.py | python3 -m json.tool`

## Ordre de déploiement logique
1. `pfsense.yml` — firewall, VPN, DNS (pfSense joignables directement)
2. `vault.yml` — Vault sur ops-vm (dépend SSH ops-vm)
3. `elk.yml` — ELK stack sur ops-vm (dépend Vault pour les tokens)
4. `elastic-agent.yml` — Fleet sur ops-vm
5. `filebeat.yml` — tous les hosts (dépend ELK up)
6. `services-vm.yml` — base role sur services-vm

## Mots de passe ELK — auto-gérés via Vault
`elk_elastic_password` / `elk_kibana_system_password` (defaults `"changeme"` dans `ansible/roles/elk/defaults/main.yml`) ne servent que de bootstrap au tout premier run.
Le rôle `elk` les stocke ensuite dans Vault (`secret/data/elk/elastic-password`, `secret/data/elk/kibana-system-password`), et les relit à chaque run suivant (cf. tâches "SECRETS DEPUIS VAULT" / "SECRETS → VAULT" en début/fin de `roles/elk/tasks/main.yml`).
Les rôles `kibana` et `filebeat` relisent ces mêmes secrets depuis Vault (plus de variable codée en dur côté consommateur) — même schéma que le token Fleet (`secret/data/elk/fleet-enrollment-token`, écrit par `kibana`, relu par `elastic-agent`).

## Collections requises
`ansible-galaxy collection install -r requirements.yml`  
Collections : `pfsensible.core`, `community.docker`

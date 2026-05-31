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

## Variables ELK à surcharger en prod
Dans `ansible/roles/elk/defaults/main.yml` :
- `elk_elastic_password: "changeme"` → à mettre dans Vault
- `elk_kibana_system_password: "changeme"` → idem

## Collections requises
`ansible-galaxy collection install -r requirements.yml`  
Collections : `pfsensible.core`, `community.docker`

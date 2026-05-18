# HashiCorp Vault — Configuration Ansible

Vault est déployé sur `ops-vm` (VM 120) en container Docker, mode Raft (single-node).

Pour la création de la VM, voir le module Terraform `ops-vm`.

---

## Caractéristiques

| Paramètre | Valeur |
|---|---|
| Version | 1.17.2 |
| Port | 8200 |
| Storage | Raft (`/opt/vault/data`) |
| Config | `/etc/vault.d/vault.hcl` |
| TLS | Désactivé (lab) |
| UI | Activée |
| Init shares | 5 |
| Init threshold | 3 |

---

## Déploiement

```bash
cd ansible
ansible-playbook -i inventory/onprem.py playbooks/vault.yml
```

Le rôle `vault` (après `base`) :
1. Crée les répertoires `/etc/vault.d` et `/opt/vault/data`
2. Déploie `vault.hcl` depuis le template Jinja2
3. Lance le container Docker Vault
4. Attend le port 8200
5. Initialise Vault si non initialisé (5 shares, threshold 3)
6. Sauvegarde `vault-init.json` sur la VM (`/root/vault-init.json`)
7. Rapatrie `vault-init.json` sur le controller Ansible (`ansible/vault-init.json`)
8. Unseal avec les 3 premières clés

---

## Accès

Vault est sur le réseau privé `vmbr1`. Ouvrir un tunnel SSH :

```bash
ssh -L 8200:OPS_IP:8200 -N root@51.75.128.134
```

Puis ouvrir dans le navigateur : `http://localhost:8200`

Login : root token (`hvs.xxx`) depuis `/root/vault-init.json` sur ops-vm.

Vérifier l'état :

```bash
ssh -o ProxyJump=root@51.75.128.134 ubuntu@OPS_IP \
  "export VAULT_ADDR=http://127.0.0.1:8200 && vault status"
```

| Champ | Valeur attendue |
|---|---|
| `Initialized` | `true` |
| `Sealed` | `false` |
| `HA Enabled` | `false` |

---

## Unseal après redémarrage

Vault se scelle à chaque redémarrage. Il faut 3 des 5 unseal keys :

```bash
ssh -o ProxyJump=root@51.75.128.134 ubuntu@OPS_IP \
  "export VAULT_ADDR=http://127.0.0.1:8200 && vault operator unseal <KEY_1>"
# répéter pour KEY_2 et KEY_3
```

Les unseal keys sont dans `/root/vault-init.json` sur ops-vm.

---

## Secrets stockés par les rôles Ansible

| Chemin Vault | Contenu | Écrit par |
|---|---|---|
| `secret/data/elk/fleet-enrollment-token` | Token enrollment Fleet régulier | rôle `elk` |

---

## Variables (ansible/roles/vault/defaults/main.yml)

| Variable | Valeur par défaut |
|---|---|
| `vault_version` | `1.17.2` |
| `vault_config_dir` | `/etc/vault.d` |
| `vault_data_dir` | `/opt/vault/data` |
| `vault_init_shares` | `5` |
| `vault_init_threshold` | `3` |
| `vault_tls_disable` | `true` |

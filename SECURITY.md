# Sécurité

## Ce qui ne doit jamais être commité

| Fichier | Contenu sensible |
|---|---|
| `terraform/envs/*/terraform.tfvars` | Tokens API, IPs, clés SSH publiques |
| `packer/**/*.pkrvars.hcl` | Tokens Packer |
| `terraform/envs/*/terraform.tfstate*` | State Terraform (contient des secrets en clair) |
| `ansible/vault-init.json` | Unseal keys + root token HashiCorp Vault |
| `.env` | Variables d'environnement locales |

Tous ces patterns sont dans `.gitignore`. Vérifier avec `git status` avant chaque commit.

---

## Tokens Proxmox

Le projet utilise deux tokens :

| Token | Usage | Permissions |
|---|---|---|
| `root@pam!terraform` | Terraform — crée/détruit les VMs | `TerraformRole` sur `/` |
| `root@pam!packer` | Packer — build les templates | `PVEVMAdmin` + `Datastore.AllocateTemplate` |

Les tokens sont créés et leurs permissions assignées par `terraform/envs/bootstrap/` — **aucune action manuelle sur Proxmox n'est nécessaire**.

Injection des tokens :
```bash
# Jamais de guillemets doubles — le ! serait interprété par bash
export TF_VAR_proxmox_api_token='root@pam!terraform=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
```

---

## Unseal keys HashiCorp Vault

Après l'init Vault, les unseal keys sont sauvegardées dans `/root/vault-init.json` sur vault-vm.

En lab : ce fichier reste sur la VM, ignoré par git. Il est aussi uploadé comme artefact CI éphémère (retention 1 jour).

En production : stocker les unseal keys dans un HSM ou un secrets manager externe, jamais sur le même serveur que Vault.

---

## TLS

Tous les appels API Proxmox utilisent `insecure = true` (certificat auto-signé). Acceptable pour un lab isolé, à remplacer par un certificat valide en production.

HashiCorp Vault tourne en HTTP (`tls_disable = true` dans `vault.hcl`). À activer avec un certificat TLS avant toute exposition réseau.

---

## Secrets dans le dépôt

Aucun secret ne doit apparaître dans le code. Si tu en trouves un :

1. Révoquer immédiatement le secret compromis (Proxmox UI → API Tokens → Delete)
2. Générer un nouveau secret
3. Purger l'historique git : `git filter-repo --path fichier --invert-paths`
4. Force-pusher (après accord de l'équipe)

---

## GitHub Actions

Les secrets CI sont stockés dans `Settings → Secrets and variables → Actions` du dépôt.

| Secret | Description |
|---|---|
| `PROXMOX_API_TOKEN` | `root@pam!terraform=<uuid>` |
| `PROXMOX_PACKER_TOKEN` | `root@pam!packer=<uuid>` |
| `ANSIBLE_SSH_PRIVATE_KEY_PATH` | Chemin de la clé SSH sur le runner |

Le runner est self-hosted et doit être sur le réseau local Proxmox pour accéder aux VMs.

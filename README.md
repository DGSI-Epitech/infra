## Terraform – Commandes standardisées

Ce projet utilise un `package.json` comme point d'entrée unique pour exécuter les commandes Terraform, afin de garantir une expérience identique sur Windows, macOS et Linux.

---

### Prérequis

- Node.js ≥ 18
- Git
- Ansible (pour la configuration des VMs après déploiement)
- Accès réseau à l'API Proxmox (selon l'environnement)

> Terraform n'a pas besoin d'être installé manuellement : `npm run setup` s'en charge.

---

## Installation

```bash
npm run setup
```

Détecte l'OS et installe Terraform via le gestionnaire de paquets approprié (Chocolatey, Homebrew ou APT).

---

## Variables & Secrets

Copier le fichier d'exemple et remplir les valeurs :

```bash
cp terraform/envs/onprem/terraform.tfvars.example terraform/envs/onprem/terraform.tfvars
```

Le token Proxmox ne doit jamais être dans un fichier — il s'injecte uniquement via variable d'environnement (single quotes obligatoires pour éviter que bash interprète `!`) :

```bash
export TF_VAR_proxmox_api_token='root@pam!terraform=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
```

Pour le détail complet (création du token, permissions, SSH) : voir [`docs/runbooks/RUNBOOKS.md`](docs/runbooks/RUNBOOKS.md).

---

## Vérifications locales (avant un push)

```bash
npm run tf:check
```

Exécute dans l'ordre : formatage, validation onprem, validation remote.

---

## Environnement on-prem (DEV)

```bash
npm run tf:init:onprem
npm run tf:plan:onprem
terraform -chdir=terraform/envs/onprem apply
```

---

## Environnement remote (PROD)

```bash
npm run tf:init:remote
npm run tf:plan:remote
```

Le `terraform apply` en production est désactivé en local — il passe obligatoirement par la CI/CD.

---

## Configuration des VMs (Ansible)

Après qu'une VM est up, appliquer le playbook correspondant :

```bash
cd ansible
ansible-playbook playbooks/services-vm.yml
```

L'inventory est dans `ansible/inventory/onprem.yml`.

---

## Sécurité & GitOps

- Aucun secret dans le dépôt (tokens, mots de passe)
- Les credentials sont injectés via variables d'environnement ou secrets CI/CD
- `*.tfstate` et `*.tfvars` sont ignorés par git
- Toute modification passe par une Pull Request avec revue
- Toute modification en production passe par la CI/CD

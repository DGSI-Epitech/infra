# Règles Git — Workflow PR

## Principe absolu

**Ne jamais commiter directement sur `main`.** Toute modification passe par une feature branch et une PR.

## Workflow obligatoire

1. **Créer la feature branch EN PREMIER**, avant tout commit :
   ```bash
   git checkout -b feat/<nom-descriptif>
   # ou fix/<nom>, docs/<nom>, chore/<nom>
   ```

2. **Commiter sur la feature branch** (jamais sur main)

3. **Pousser la feature branch** :
   ```bash
   git push -u origin feat/<nom>
   ```

4. **Créer la PR** avec `gh pr create --base main --head feat/<nom>`

## Nommage des branches

- `feat/` — nouvelle fonctionnalité
- `fix/` — correction de bug
- `docs/` — documentation uniquement
- `chore/` — maintenance, nettoyage

## Avant de commencer un nouveau travail

Vérifier la branche courante :
```bash
git branch --show-current
```

Si la réponse est `main` → créer une branche avant tout.

## Ce qu'il ne faut jamais faire

- `git commit` quand `git branch --show-current` retourne `main`
- `git push origin main`
- `git push` sans avoir vérifié qu'on est sur une feature branch

#!/usr/bin/env bash
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$REPO_ROOT/logs"
LOG_ONPREM="$LOG_DIR/deploy-onprem.log"
LOG_REMOTE="$LOG_DIR/deploy-remote.log"

mkdir -p "$LOG_DIR"

echo "==> Déploiement PVE1 (onprem) + PVE2 (remote) en parallèle"
echo ""

bash "$REPO_ROOT/scripts/deploy.sh"        > "$LOG_ONPREM" 2>&1 &
PID_ONPREM=$!

bash "$REPO_ROOT/scripts/deploy-remote.sh" > "$LOG_REMOTE" 2>&1 &
PID_REMOTE=$!

echo "    PVE1 (PID ${PID_ONPREM}) → tail -f logs/deploy-onprem.log"
echo "    PVE2 (PID ${PID_REMOTE}) → tail -f logs/deploy-remote.log"
echo ""

wait "$PID_ONPREM"
RC_ONPREM=$?

wait "$PID_REMOTE"
RC_REMOTE=$?

echo ""
if [[ $RC_ONPREM -eq 0 ]]; then
  echo "    [OK]  PVE1 — déploiement terminé"
else
  echo "    [ERR] PVE1 — échec (code ${RC_ONPREM}) — voir logs/deploy-onprem.log"
fi

if [[ $RC_REMOTE -eq 0 ]]; then
  echo "    [OK]  PVE2 — déploiement terminé"
else
  echo "    [ERR] PVE2 — échec (code ${RC_REMOTE}) — voir logs/deploy-remote.log"
fi

[[ $RC_ONPREM -eq 0 && $RC_REMOTE -eq 0 ]]

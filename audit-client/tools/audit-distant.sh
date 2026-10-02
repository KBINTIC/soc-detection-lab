#!/bin/bash
# audit-distant.sh - lance l'audit sur un poste du MEME reseau, sans cle USB.
#   Mac client :   ./audit-distant.sh mac  user@ip-du-mac   [NomClient]
#   (SSH doit etre active sur le poste : Reglages > Partage > Connexion a distance)
# Les rapports reviennent dans ../missions/<courante>/rapports/ via le lanceur.
set -euo pipefail
KIND="${1:-}"; TARGET="${2:-}"; CLIENT="${3:-}"
OUT="${OUTDIR:-./rapports}"; mkdir -p "$OUT"
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ "$KIND" != "mac" ] || [ -z "$TARGET" ]; then
  echo "Usage: $0 mac user@ip [NomClient]"
  echo "Pour Windows distant : utiliser WinRM/PSRemoting (voir RUNBOOK), ou la cle USB."
  exit 1
fi
echo "Copie de l'audit vers $TARGET ..."
scp -q "$HERE/../kit/audit-poste-mac.command" "$TARGET:/tmp/audit-poste-mac.command"
echo "Execution a distance (sudo demandera le mot de passe du poste)..."
ssh -t "$TARGET" "cd /tmp && mkdir -p rapports && sudo bash audit-poste-mac.command '$CLIENT'"
echo "Rapatriement du rapport..."
scp -q "$TARGET:/tmp/rapports/*.json" "$OUT/"
ssh "$TARGET" "rm -rf /tmp/audit-poste-mac.command /tmp/rapports" || true
echo "OK. Rapport(s) dans $OUT"

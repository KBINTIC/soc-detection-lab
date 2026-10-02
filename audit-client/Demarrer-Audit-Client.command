#!/bin/bash
# Demarrer-Audit-Client.command - ORCHESTRATEUR de la mission d'audit (a lancer sur le Mac consultant).
# Prepare le kit, lance les audits (local Mac / distant / USB), genere le rapport PDF.
cd "$(dirname "$0")"
BASE="$(pwd)"
say(){ printf '\n\033[1;36m== %s ==\033[0m\n' "$1"; }

# 1) Mission : dossier date + client
read -r -p "Nom du client : " CLIENT
[ -z "$CLIENT" ] && CLIENT="Client"
SAFE=$(echo "$CLIENT" | tr -cd '[:alnum:]-_ ' | tr ' ' '_')
MISSION="$BASE/missions/$(date +%Y%m%d)_$SAFE"
mkdir -p "$MISSION/rapports"
echo "Mission : $MISSION"

while true; do
  cat <<MENU

Client : $CLIENT    Rapports collectes : $(ls "$MISSION/rapports"/*.json 2>/dev/null | wc -l | tr -d ' ')
  1) Preparer la cle USB (copier le kit d'audit)
  2) Auditer CE Mac (poste courant)
  3) Auditer un Mac a distance (SSH)
  4) Importer des rapports depuis une cle USB
  5) Generer le RAPPORT D'AUDIT (PDF)
  6) Ouvrir le mode operatoire (RUNBOOK)
  0) Quitter
MENU
  read -r -p "Choix : " CH
  case "$CH" in
    1) read -r -p "Chemin de la cle USB (ex: /Volumes/AUDIT) : " USB
       if [ -d "$USB" ]; then mkdir -p "$USB/AuditKit"; cp -R kit/* "$USB/AuditKit/"; mkdir -p "$USB/AuditKit/rapports"
          echo "Kit copie dans $USB/AuditKit (Windows: Lancer-Audit-Windows.bat ; Mac: audit-poste-mac.command)"
       else echo "Dossier introuvable."; fi ;;
    2) say "Audit du Mac courant (sudo recommande)"
       sudo OUTDIR="$MISSION/rapports" bash kit/audit-poste-mac.command "$CLIENT" ;;
    3) read -r -p "Cible SSH (user@ip du Mac client) : " TGT
       OUTDIR="$MISSION/rapports" bash tools/audit-distant.sh mac "$TGT" "$CLIENT" ;;
    4) read -r -p "Chemin des rapports sur la cle (ex: /Volumes/AUDIT/AuditKit/rapports) : " SRC
       if [ -d "$SRC" ]; then cp -f "$SRC"/*.json "$MISSION/rapports/" 2>/dev/null && echo "Importe." ; else echo "Introuvable."; fi ;;
    5) say "Generation du rapport"
       python3 tools/generer_rapport.py "$MISSION"
       LAST=$(ls -t "$MISSION"/Rapport-Audit-*.pdf 2>/dev/null | head -1)
       [ -n "$LAST" ] && open "$LAST" || open "$MISSION"/Rapport-Audit-*.html 2>/dev/null ;;
    6) open RUNBOOK.html ;;
    0) echo "Fin."; break ;;
    *) echo "Choix invalide." ;;
  esac
done

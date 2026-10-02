#!/bin/bash
# audit-poste-mac.command - AUDIT EN LECTURE SEULE d'un poste macOS.
# Ne modifie RIEN. Produit un rapport JSON (schema commun PC/Mac) dans ./rapports/.
# Certains contrôles nécessitent sudo : lancez de préférence avec  sudo.
#   Terminal:  sudo bash "audit-poste-mac.command"    (ou double-clic puis saisie du mot de passe si demandé)
set -u
cd "$(dirname "$0")"
CLIENT="${1:-}"
OUT="${OUTDIR:-./rapports}"; mkdir -p "$OUT"
START=$(date +%s); STAMP=$(date +%Y%m%d-%H%M%S); ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
HOST=$(scutil --get ComputerName 2>/dev/null || hostname)
OSV=$(sw_vers -productName 2>/dev/null)" "$(sw_vers -productVersion 2>/dev/null)
USR=$(stat -f%Su /dev/console 2>/dev/null || whoami)
ROOT=0; [ "$(id -u)" = "0" ] && ROOT=1

TMP=$(mktemp)
# emit: ID<TAB>CAT<TAB>RISQUE<TAB>STATUT<TAB>ACTUEL<TAB>TITRE<TAB>POURQUOI<TAB>CORRECTION
emit(){ printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" >> "$TMP"; }
need_sudo(){ [ "$ROOT" = "1" ] && return 0 || return 1; }

echo; echo "=== Audit (lecture seule) - $HOST ==="

# FW-MAC-001 Pare-feu applicatif
FWS=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null)
if echo "$FWS" | grep -qi "enabled"; then emit FW-MAC-001 "Pare-feu" Haut Conforme "Pare-feu applicatif actif" "Pare-feu applicatif actif" "Bloque les connexions entrantes non sollicitées vers les apps." "socketfilterfw --setglobalstate on"
else emit FW-MAC-001 "Pare-feu" Haut NonConforme "Pare-feu désactivé" "Pare-feu applicatif actif" "Bloque les connexions entrantes non sollicitées vers les apps." "sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on"; fi

# FW-MAC-002 Mode furtif
STL=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode 2>/dev/null)
if echo "$STL" | grep -qi "enabled"; then emit FW-MAC-002 "Pare-feu" Bas Conforme "Mode furtif actif" "Mode furtif du pare-feu" "Ignore les requêtes de découverte (ping), réduit la visibilité du poste." ""
else emit FW-MAC-002 "Pare-feu" Bas NonConforme "Mode furtif inactif" "Mode furtif du pare-feu" "Ignore les requêtes de découverte (ping), réduit la visibilité du poste." "sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on"; fi

# FV-001 FileVault
FV=$(fdesetup status 2>/dev/null)
if echo "$FV" | grep -qi "On"; then emit FV-001 "Chiffrement" Haut Conforme "FileVault actif" "Chiffrement du disque (FileVault)" "Protège les données au repos en cas de vol du Mac." ""
else emit FV-001 "Chiffrement" Haut NonConforme "FileVault inactif" "Chiffrement du disque (FileVault)" "Protège les données au repos en cas de vol du Mac." "(manuel) Réglages > Confidentialité et sécurité > FileVault + sauvegarder la clé"; fi

# GK-001 Gatekeeper
GK=$(spctl --status 2>/dev/null)
if echo "$GK" | grep -qi "assessments enabled"; then emit GK-001 "Intégrité" Moyen Conforme "Gatekeeper actif" "Gatekeeper" "N'autorise que les apps signées/notariées, bloque les binaires inconnus." ""
else emit GK-001 "Intégrité" Moyen NonConforme "Gatekeeper désactivé" "Gatekeeper" "N'autorise que les apps signées/notariées, bloque les binaires inconnus." "sudo spctl --master-enable"; fi

# SIP-001 System Integrity Protection
SIP=$(csrutil status 2>/dev/null)
if echo "$SIP" | grep -qi "enabled"; then emit SIP-001 "Intégrité" Haut Conforme "SIP actif" "System Integrity Protection" "Empêche la modification des fichiers système, même par root." ""
else emit SIP-001 "Intégrité" Haut NonConforme "SIP désactivé" "System Integrity Protection" "Empêche la modification des fichiers système, même par root." "(manuel, Recovery) csrutil enable"; fi

# UPD-001 Mises à jour auto
AUC=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled 2>/dev/null)
if [ "$AUC" = "1" ]; then emit UPD-001 "Mises à jour" Haut Conforme "Vérification auto activée" "Mises à jour automatiques" "Un poste non à jour cumule des vulnérabilités connues." ""
else emit UPD-001 "Mises à jour" Haut NonConforme "Vérification auto désactivée/inconnue" "Mises à jour automatiques" "Un poste non à jour cumule des vulnérabilités connues." "sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true"; fi

# RL-001 Connexion à distance (SSH)
if need_sudo; then
  RL=$(systemsetup -getremotelogin 2>/dev/null)
  if echo "$RL" | grep -qi "Off"; then emit RL-001 "Accès distant" Moyen Conforme "SSH désactivé" "Connexion à distance (SSH)" "Un service SSH ouvert élargit la surface d'attaque s'il n'est pas nécessaire." ""
  else emit RL-001 "Accès distant" Moyen NonConforme "SSH ACTIVÉ" "Connexion à distance (SSH)" "Un service SSH ouvert élargit la surface d'attaque s'il n'est pas nécessaire." "sudo systemsetup -setremotelogin off"; fi
else emit RL-001 "Accès distant" Moyen NA "Nécessite sudo" "Connexion à distance (SSH)" "Un service SSH ouvert élargit la surface d'attaque s'il n'est pas nécessaire." "sudo systemsetup -setremotelogin off"; fi

# GUEST-001 Compte invité
GE=$(defaults read /Library/Preferences/com.apple.loginwindow GuestEnabled 2>/dev/null)
if [ "$GE" = "1" ]; then emit GUEST-001 "Comptes" Moyen NonConforme "Compte invité ACTIF" "Compte invité désactivé" "Un compte invité offre un accès sans traçabilité." "sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false"
else emit GUEST-001 "Comptes" Moyen Conforme "Compte invité désactivé" "Compte invité désactivé" "Un compte invité offre un accès sans traçabilité." ""; fi

# LOCK-001 Mot de passe exigé à la sortie de veille (utilisateur courant)
AFP=$(sudo -u "$USR" defaults read com.apple.screensaver askForPassword 2>/dev/null)
AFPD=$(sudo -u "$USR" defaults read com.apple.screensaver askForPasswordDelay 2>/dev/null)
if [ "$AFP" = "1" ] && [ "${AFPD:-9999}" -le 60 ] 2>/dev/null; then emit LOCK-001 "Session" Moyen Conforme "Mot de passe exigé (<=60s)" "Verrouillage de session" "Un écran déverrouillé laisse l'accès libre en l'absence de l'utilisateur." ""
else emit LOCK-001 "Session" Moyen NonConforme "Mot de passe non exigé ou délai long" "Verrouillage de session" "Un écran déverrouillé laisse l'accès libre en l'absence de l'utilisateur." "defaults write com.apple.screensaver askForPassword -int 1 ; defaults write com.apple.screensaver askForPasswordDelay -int 0"; fi

# SHARE-001 Partage d'ecran / gestion a distance
if launchctl print system/com.apple.screensharing >/dev/null 2>&1; then
  emit SHARE-001 "Accès distant" Moyen NonConforme "Partage d'écran ACTIF" "Partage d'écran désactivé" "Le partage d'écran ouvert sans besoin est un accès distant à risque." "Réglages > Général > Partage > désactiver Partage d'écran"
else
  emit SHARE-001 "Accès distant" Moyen Conforme "Partage d'écran inactif" "Partage d'écran désactivé" "Le partage d'écran ouvert sans besoin est un accès distant à risque." ""
fi

# SMB-MAC-001 Partage de fichiers
if launchctl print system/com.apple.smbd >/dev/null 2>&1; then
  emit SMB-MAC-001 "Partage" Moyen NonConforme "Partage de fichiers ACTIF" "Partage de fichiers désactivé" "Un partage de fichiers actif sans besoin élargit la surface d'attaque." "Réglages > Général > Partage > désactiver Partage de fichiers"
else
  emit SMB-MAC-001 "Partage" Moyen Conforme "Partage de fichiers inactif" "Partage de fichiers désactivé" "Un partage de fichiers actif sans besoin élargit la surface d'attaque." ""
fi

# Affichage console
while IFS=$'\t' read -r id cat risque statut actuel titre pourquoi corr; do
  case "$statut" in Conforme) ic='[OK]';; NonConforme) ic='[!!]';; *) ic='[--]';; esac
  printf '  %s %-12s %s\n' "$ic" "$id" "$titre"
done < "$TMP"

END=$(date +%s); DUREE=$((END-START))
SAFEHOST=$(echo "$HOST" | tr -s " " | tr " /" "__")
OUTFILE="$OUT/rapport-Mac-$SAFEHOST-$STAMP.json"
PYBIN=$(command -v python3 || command -v /usr/bin/python3)
if [ -z "$PYBIN" ]; then echo "python3 introuvable : impossible d'écrire le JSON."; exit 1; fi
CLIENT="$CLIENT" HOST="$HOST" OSV="$OSV" USR="$USR" ISO="$ISO" DUREE="$DUREE" TMP="$TMP" OUTFILE="$OUTFILE" "$PYBIN" - <<'PY'
import os,json
rows=[]
with open(os.environ['TMP'],encoding='utf-8') as f:
    for line in f:
        p=line.rstrip('\n').split('\t')
        if len(p)<8: continue
        rows.append(dict(id=p[0],categorie=p[1],risque=p[2],statut=p[3],actuel=p[4],titre=p[5],pourquoi=p[6],correction=p[7]))
conf=sum(1 for r in rows if r['statut']=='Conforme')
nc=sum(1 for r in rows if r['statut']=='NonConforme')
na=sum(1 for r in rows if r['statut']=='NA')
appl=conf+nc
score=round(100*conf/appl) if appl else 0
rep=dict(client=os.environ['CLIENT'],poste=os.environ['HOST'],type='Mac',os=os.environ['OSV'],
         utilisateur=os.environ['USR'],horodatage=os.environ['ISO'],duree_secondes=int(os.environ['DUREE']),
         score=score,conformes=conf,non_conformes=nc,non_applicable=na,controles=rows)
open(os.environ['OUTFILE'],'w',encoding='utf-8').write(json.dumps(rep,ensure_ascii=False,indent=2))
print("\nDurée: %ss  |  Score: %s%%  |  Écarts: %s"%(os.environ['DUREE'],score,nc))
print("Rapport JSON:",os.environ['OUTFILE'])
PY
[ -n "${SUDO_UID:-}" ] && chown "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$OUTFILE" 2>/dev/null
rm -f "$TMP"
echo "Rapatriez le dossier 'rapports' sur le Mac consultant, puis générez le rapport PDF."

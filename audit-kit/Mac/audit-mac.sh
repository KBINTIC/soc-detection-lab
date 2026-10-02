#!/bin/bash
# audit-mac.sh - Audit de securite d'un Mac client (LECTURE SEULE). Ne modifie rien.
# Lance par Demarrer-Audit.command (qui l'execute avec sudo pour lire certains reglages).
set -u
T0=$(date +%s)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KIT_ROOT="$(dirname "$SCRIPT_DIR")"
POSTES="$KIT_ROOT/postes"
STAMP="$(date +%Y%m%d-%H%M%S)"
HOSTS="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
POSTE_ID="${HOSTS}-MAC-${STAMP}"
OUT="$POSTES/$POSTE_ID"
mkdir -p "$OUT"

OSV="$(sw_vers -productName) $(sw_vers -productVersion)"
USER_REAL="${SUDO_USER:-$USER}"

JSON_ITEMS=""
ROWS=""
NC=0; CONF=0; APPLIC=0
esc(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

add(){ # id cat risque titre pourquoi statut actuel
  local id="$1" cat="$2" risque="$3" titre="$4" pourquoi="$5" statut="$6" actuel="$7"
  local comma=""; [ -n "$JSON_ITEMS" ] && comma=","
  JSON_ITEMS="$JSON_ITEMS$comma{\"Id\":\"$(esc "$id")\",\"Categorie\":\"$(esc "$cat")\",\"Risque\":\"$(esc "$risque")\",\"Titre\":\"$(esc "$titre")\",\"Pourquoi\":\"$(esc "$pourquoi")\",\"Statut\":\"$statut\",\"Actuel\":\"$(esc "$actuel")\"}"
  local badge cls label; case "$statut" in Conforme) cls=ok;label=Conforme; CONF=$((CONF+1)); APPLIC=$((APPLIC+1));; NonConforme) cls=ko;label="Non conforme"; NC=$((NC+1)); APPLIC=$((APPLIC+1));; *) cls=na;label="N/A";; esac
  ROWS="$ROWS<tr><td class='m'>$id</td><td>$titre<div class='w'>$pourquoi</div></td><td>$risque</td><td><span class='b $cls'>$label</span></td><td class='w'>$(printf '%s' "$actuel" | sed 's/&/\&amp;/g; s/</\&lt;/g')</td></tr>"
  local ic col; case "$statut" in Conforme) ic='[OK]';col=32;; NonConforme) ic='[!!]';col=31;; *) ic='[--]';col=90;; esac
  printf "  \033[%sm%s %-12s %s\033[0m\n" "$col" "$ic" "$id" "$titre"
}

echo "=== Audit macOS (lecture seule) - $HOSTS ==="

# FW-001 Pare-feu applicatif
fw="$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null)"
if echo "$fw" | grep -qi 'enabled'; then add FW-001 "Pare-feu" Haut "Pare-feu applicatif actif" "Bloque les connexions entrantes non sollicitees vers les apps." Conforme "Pare-feu actif"
else add FW-001 "Pare-feu" Haut "Pare-feu applicatif actif" "Bloque les connexions entrantes non sollicitees vers les apps." NonConforme "Pare-feu desactive"; fi

# FW-002 Mode furtif
st="$(/usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode 2>/dev/null)"
if echo "$st" | grep -qi 'enabled'; then add FW-002 "Pare-feu" Bas "Mode furtif active" "Le poste ne repond pas aux pings/scans, reduisant sa visibilite reseau." Conforme "Mode furtif actif"
else add FW-002 "Pare-feu" Bas "Mode furtif active" "Le poste ne repond pas aux pings/scans, reduisant sa visibilite reseau." NonConforme "Mode furtif inactif"; fi

# FV-001 FileVault
fv="$(fdesetup status 2>/dev/null)"
if echo "$fv" | grep -qi 'FileVault is On'; then add FV-001 "Chiffrement" Haut "Chiffrement FileVault actif" "Sans chiffrement, un vol de Mac donne acces aux donnees du disque." Conforme "FileVault actif"
else add FV-001 "Chiffrement" Haut "Chiffrement FileVault actif" "Sans chiffrement, un vol de Mac donne acces aux donnees du disque." NonConforme "FileVault inactif"; fi

# GK-001 Gatekeeper
gk="$(spctl --status 2>/dev/null)"
if echo "$gk" | grep -qi 'assessments enabled'; then add GK-001 "Integrite" Haut "Gatekeeper actif" "N'autorise que les apps signees/notariees, limitant l'execution de logiciels malveillants." Conforme "Gatekeeper actif"
else add GK-001 "Integrite" Haut "Gatekeeper actif" "N'autorise que les apps signees/notariees, limitant l'execution de logiciels malveillants." NonConforme "Gatekeeper desactive"; fi

# SIP-001 System Integrity Protection
sip="$(csrutil status 2>/dev/null)"
if echo "$sip" | grep -qi 'enabled'; then add SIP-001 "Integrite" Haut "Protection de l'integrite systeme (SIP)" "Empeche la modification des fichiers systeme proteges, meme par root." Conforme "SIP actif"
else add SIP-001 "Integrite" Haut "Protection de l'integrite systeme (SIP)" "Empeche la modification des fichiers systeme proteges, meme par root." NonConforme "SIP desactive"; fi

# UPD-001 Mises a jour automatiques
auto="$(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled 2>/dev/null)"
if [ "$auto" = "1" ]; then add UPD-001 "Mises a jour" Haut "Recherche automatique des mises a jour" "Un Mac non a jour expose des vulnerabilites connues." Conforme "Recherche auto activee"
else add UPD-001 "Mises a jour" Haut "Recherche automatique des mises a jour" "Un Mac non a jour expose des vulnerabilites connues." NonConforme "Recherche auto desactivee"; fi

# SSH-001 Connexion a distance (SSH)
rl="$(systemsetup -getremotelogin 2>/dev/null)"
if echo "$rl" | grep -qi 'Off'; then add SSH-001 "Acces distant" Moyen "Connexion a distance (SSH) desactivee" "SSH expose une surface d'attaque ; a couper si non utilise." Conforme "SSH desactive"
elif echo "$rl" | grep -qi 'On'; then add SSH-001 "Acces distant" Moyen "Connexion a distance (SSH) desactivee" "SSH expose une surface d'attaque ; a couper si non utilise." NonConforme "SSH ACTIF (a verifier)"
else add SSH-001 "Acces distant" Moyen "Connexion a distance (SSH) desactivee" "SSH expose une surface d'attaque ; a couper si non utilise." NA "Etat indisponible"; fi

# SHARE-001 Partage d'ecran / gestion a distance
if launchctl print system/com.apple.screensharing >/dev/null 2>&1; then add SHARE-001 "Acces distant" Moyen "Partage d'ecran desactive" "Le partage d'ecran ouvert sans besoin est un acces distant a risque." NonConforme "Partage d'ecran ACTIF"
else add SHARE-001 "Acces distant" Moyen "Partage d'ecran desactive" "Le partage d'ecran ouvert sans besoin est un acces distant a risque." Conforme "Partage d'ecran inactif"; fi

# SMB-001 Partage de fichiers
if launchctl print system/com.apple.smbd >/dev/null 2>&1; then add SMB-001 "Partage" Moyen "Partage de fichiers desactive" "Un partage de fichiers actif sans besoin elargit la surface d'attaque." NonConforme "Partage de fichiers ACTIF"
else add SMB-001 "Partage" Moyen "Partage de fichiers desactive" "Un partage de fichiers actif sans besoin elargit la surface d'attaque." Conforme "Partage de fichiers inactif"; fi

# GUEST-001 Compte invite
ge="$(defaults read /Library/Preferences/com.apple.loginwindow GuestEnabled 2>/dev/null)"
if [ "$ge" = "1" ]; then add GUEST-001 "Comptes" Moyen "Compte invite desactive" "Un compte invite actif offre un acces anonyme sans tracabilite." NonConforme "Invite ACTIF"
else add GUEST-001 "Comptes" Moyen "Compte invite desactive" "Un compte invite actif offre un acces anonyme sans tracabilite." Conforme "Invite desactive"; fi

DUR=$(( $(date +%s) - T0 ))
SCORE=0; [ "$APPLIC" -gt 0 ] && SCORE=$(( 100 * CONF / APPLIC ))
TS="$(date +%Y-%m-%dT%H:%M:%S)"
NAPP=$(( $(echo "$JSON_ITEMS" | grep -o '"Statut":"NA"' | wc -l | tr -d ' ') ))

cat > "$OUT/audit.json" <<JSON
{"Poste":"$(esc "$HOSTS")","Systeme":"Mac","OSDetail":"$(esc "$OSV")","Utilisateur":"$(esc "$USER_REAL")","Horodatage":"$TS","DureeSecondes":$DUR,"Score":$SCORE,"Conformes":$CONF,"NonConformes":$NC,"NonApplicable":$NAPP,"Controles":[$JSON_ITEMS]}
JSON

cat > "$OUT/rapport-poste.html" <<HTML
<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>Audit $HOSTS</title>
<style>body{font:14px/1.5 -apple-system,Segoe UI,Roboto,sans-serif;color:#1a2230;margin:24px;max-width:980px}
h1{font-size:20px;margin:0 0 2px}.s{color:#5b6677;margin:0 0 16px}
.k{display:flex;gap:12px;flex-wrap:wrap;margin:14px 0}.c{border:1px solid #e6e9ef;border-radius:10px;padding:12px 16px}.c .n{font-size:24px;font-weight:700}.c .l{color:#5b6677;font-size:12px}
table{width:100%;border-collapse:collapse;border:1px solid #e6e9ef;border-radius:10px;overflow:hidden}
th,td{text-align:left;padding:9px 11px;border-bottom:1px solid #e6e9ef;vertical-align:top}
th{font-size:11px;text-transform:uppercase;color:#5b6677}.m{font-family:ui-monospace,Consolas,monospace;font-size:12px;color:#5b6677}
.w{color:#5b6677;font-size:12.5px;max-width:46ch}.b{padding:2px 9px;border-radius:999px;font-size:12px;font-weight:600}
.b.ok{background:#d9f0e4;color:#1a7f52}.b.ko{background:#f6dcde;color:#c23b45}.b.na{background:#e7eaef;color:#8893a4}
.ft{color:#5b6677;font-size:12px;margin-top:14px}</style></head><body>
<h1>Rapport d'audit (avant correction) &mdash; $HOSTS</h1>
<p class="s">$OSV &middot; $USER_REAL &middot; $(date '+%d/%m/%Y %H:%M') &middot; duree de l'audit : ${DUR}s</p>
<div class="k"><div class="c"><div class="n">${SCORE}%</div><div class="l">Conformite</div></div>
<div class="c"><div class="n">${NC}</div><div class="l">Ecarts detectes</div></div>
<div class="c"><div class="n">${APPLIC}</div><div class="l">Controles applicables</div></div></div>
<table><thead><tr><th>ID</th><th>Controle</th><th>Risque</th><th>Statut</th><th>Etat releve</th></tr></thead><tbody>
$ROWS
</tbody></table>
<p class="ft">Audit en lecture seule &mdash; aucune modification effectuee. Bahiri Consultant IT MSP Cybersecurite.</p>
</body></html>
HTML

echo ""
echo "Audit termine en ${DUR}s. $NC ecart(s) sur $APPLIC controles applicables."
echo "Rapport du poste : $OUT"
open "$OUT/rapport-poste.html" 2>/dev/null || true

<#
  audit-windows.ps1  —  Audit de securite d'un poste Windows (LECTURE SEULE)
  Ne modifie RIEN. Chronometre l'audit, ecrit un rapport par poste sous ..\postes\.
  Lance par Demarrer-Audit.cmd (clic droit > executer en tant qu'administrateur).
#>
$ErrorActionPreference = 'Stop'
$t0 = Get-Date

# Dossier de sortie partage (sur la cle USB) : <racine kit>\postes\<poste>-<date>\
$KitRoot    = Split-Path -Parent $PSScriptRoot
$PostesDir  = Join-Path $KitRoot 'postes'
$stamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
$posteId    = "{0}-WIN-{1}" -f $env:COMPUTERNAME, $stamp
$OutDir     = Join-Path $PostesDir $posteId
New-Item -ItemType Directory -Force $OutDir | Out-Null

function C($id,$cat,$risque,$titre,$pourquoi,$verif){
  [pscustomobject]@{Id=$id;Categorie=$cat;Risque=$risque;Titre=$titre;Pourquoi=$pourquoi;Verifier=$verif}
}
$controls = @(
  C 'FW-001' 'Pare-feu' 'Haut' 'Pare-feu Windows actif sur les trois profils' `
    "Premiere barriere contre les connexions non sollicitees. Un profil desactive ouvre le poste sur le reseau." `
    { $off=@(Get-NetFirewallProfile|Where-Object Enabled -eq $false); if($off.Count -eq 0){@{Statut='Conforme';Actuel='Domain/Private/Public : actifs'}}else{@{Statut='NonConforme';Actuel=('Desactive : '+($off.Name -join ', '))}} }
  C 'AV-001' 'Antivirus / EDR' 'Haut' 'Protection en temps reel active' `
    "Sans temps reel, un fichier malveillant n'est analyse qu'a la demande. Sous EDR tiers (GravityZone), Defender est passif : non applicable." `
    { try{$mp=Get-MpComputerStatus -ErrorAction Stop; if($mp.AMRunningMode -eq 'Passive mode'){@{Statut='NA';Actuel='Defender passif (EDR tiers)'}}elseif($mp.RealTimeProtectionEnabled){@{Statut='Conforme';Actuel='Temps reel actif'}}else{@{Statut='NonConforme';Actuel='Temps reel desactive'}} }catch{@{Statut='NA';Actuel='Defender absent / EDR tiers'}} }
  C 'SMB-001' 'Protocoles reseau' 'Haut' 'SMBv1 desactive' `
    "SMBv1 est obsolete et vulnerable (WannaCry/EternalBlue). Aucun usage moderne ne le necessite." `
    { $f=Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue; if(-not $f -or $f.State -ne 'Enabled'){@{Statut='Conforme';Actuel='SMBv1 absent/desactive'}}else{@{Statut='NonConforme';Actuel='SMBv1 active'}} }
  C 'LLMNR-001' 'Protocoles reseau' 'Moyen' 'LLMNR desactive' `
    "LLMNR permet une resolution en diffusion detournee (Responder) pour capturer des identifiants. A desactiver au profit du DNS." `
    { $v=Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Name EnableMulticast -ErrorAction SilentlyContinue; if($v -and $v.EnableMulticast -eq 0){@{Statut='Conforme';Actuel='EnableMulticast=0'}}else{@{Statut='NonConforme';Actuel='LLMNR actif'}} }
  C 'NTLM-001' 'Authentification' 'Moyen' 'NTLMv2 impose (LmCompatibilityLevel = 5)' `
    "LM/NTLMv1 ont des empreintes faciles a rejouer. Le niveau 5 n'accepte que NTLMv2." `
    { $v=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name LmCompatibilityLevel -ErrorAction SilentlyContinue; if($v -and $v.LmCompatibilityLevel -ge 5){@{Statut='Conforme';Actuel="Niveau $($v.LmCompatibilityLevel)"}}else{@{Statut='NonConforme';Actuel=('Niveau '+$(if($v){$v.LmCompatibilityLevel}else{'non defini'}))}} }
  C 'RDP-001' 'Acces distant' 'Moyen' "Si RDP actif, authentification NLA exigee" `
    "NLA oblige a s'authentifier avant d'ouvrir la session RDP, reduisant l'exposition pre-authentification. RDP coupe = sans objet." `
    { $deny=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -ErrorAction SilentlyContinue).fDenyTSConnections; if($deny -ne 0){@{Statut='NA';Actuel='RDP desactive'}}else{$nla=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -ErrorAction SilentlyContinue).UserAuthentication; if($nla -eq 1){@{Statut='Conforme';Actuel='RDP actif, NLA exige'}}else{@{Statut='NonConforme';Actuel='RDP actif sans NLA'}}} }
  C 'GUEST-001' 'Comptes' 'Moyen' 'Compte invite desactive' `
    "Un compte invite actif offre un acces anonyme sans tracabilite." `
    { $g=Get-LocalUser|Where-Object{ $_.SID.Value -like '*-501' }; if(-not $g){@{Statut='NA';Actuel='Invite introuvable'}}elseif(-not $g.Enabled){@{Statut='Conforme';Actuel='Invite desactive'}}else{@{Statut='NonConforme';Actuel='Invite ACTIF'}} }
  C 'BITLOCKER-001' 'Chiffrement' 'Haut' 'Chiffrement BitLocker du disque systeme' `
    "Sans chiffrement, un vol de poste donne acces aux donnees en retirant le disque." `
    { try{$bl=Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop; if($bl.ProtectionStatus -eq 'On'){@{Statut='Conforme';Actuel='BitLocker actif'}}else{@{Statut='NonConforme';Actuel="BitLocker inactif ($($bl.VolumeStatus))"}} }catch{@{Statut='NonConforme';Actuel='BitLocker indisponible'}} }
  C 'UPDATE-001' 'Mises a jour' 'Haut' 'Mises a jour Windows recentes' `
    "Un poste non a jour expose des vulnerabilites connues. On verifie la date du dernier correctif installe." `
    { try{$h=Get-HotFix|Sort-Object InstalledOn -Descending|Select-Object -First 1; $days=((Get-Date)-$h.InstalledOn).Days; if($days -le 45){@{Statut='Conforme';Actuel="Dernier correctif il y a $days j"}}else{@{Statut='NonConforme';Actuel="Dernier correctif il y a $days j"}} }catch{@{Statut='NA';Actuel='Historique indisponible'}} }
  C 'PSLOG-001' 'Journalisation' 'Moyen' 'Journalisation des blocs de script PowerShell' `
    "Elle enregistre le code PowerShell reellement execute, source essentielle de detection et d'investigation." `
    { $v=Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' -Name EnableScriptBlockLogging -ErrorAction SilentlyContinue; if($v -and $v.EnableScriptBlockLogging -eq 1){@{Statut='Conforme';Actuel='Activee'}}else{@{Statut='NonConforme';Actuel='Desactivee'}} }
)

Write-Host "=== Audit Windows (lecture seule) - $env:COMPUTERNAME ===" -ForegroundColor Cyan
$results = foreach($c in $controls){
  $r = & $c.Verifier
  $icon = switch($r.Statut){'Conforme'{'[OK]'}'NonConforme'{'[!!]'}default{'[--]'}}
  $col  = switch($r.Statut){'Conforme'{'Green'}'NonConforme'{'Red'}default{'DarkGray'}}
  Write-Host ("  {0} {1,-11} {2}" -f $icon,$c.Id,$c.Titre) -ForegroundColor $col
  [pscustomobject]@{Id=$c.Id;Titre=$c.Titre;Categorie=$c.Categorie;Risque=$c.Risque;Pourquoi=$c.Pourquoi;Statut=$r.Statut;Actuel=$r.Actuel}
}

$dur = [math]::Round(((Get-Date)-$t0).TotalSeconds,1)
$applic = @($results|Where-Object Statut -ne 'NA')
$conf   = @($results|Where-Object Statut -eq 'Conforme').Count
$nc     = @($results|Where-Object Statut -eq 'NonConforme').Count
$score  = if($applic.Count -gt 0){[math]::Round(100*$conf/$applic.Count)}else{0}

$report = [pscustomobject]@{
  Poste=$env:COMPUTERNAME; Systeme='Windows'; OSDetail=(Get-CimInstance Win32_OperatingSystem).Caption
  Utilisateur="$env:USERDOMAIN\$env:USERNAME"; Horodatage=(Get-Date).ToString('o')
  DureeSecondes=$dur; Score=$score; Conformes=$conf; NonConformes=$nc; NonApplicable=@($results|Where-Object Statut -eq 'NA').Count
  Controles=$results
}
$json = Join-Path $OutDir 'audit.json'
$report | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $json

# Rapport HTML du poste (autonome)
function Bd($s){switch($s){'Conforme'{'<span class="b ok">Conforme</span>'}'NonConforme'{'<span class="b ko">Non conforme</span>'}default{'<span class="b na">N/A</span>'}}}
$rows = ($results | ForEach-Object { "<tr><td class='m'>$($_.Id)</td><td>$($_.Titre)<div class='w'>$($_.Pourquoi)</div></td><td>$($_.Risque)</td><td>$(Bd $_.Statut)</td><td class='w'>$($_.Actuel)</td></tr>" }) -join "`n"
$html = @"
<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>Audit $($env:COMPUTERNAME)</title>
<style>body{font:14px/1.5 -apple-system,Segoe UI,Roboto,sans-serif;color:#1a2230;margin:24px;max-width:980px}
h1{font-size:20px;margin:0 0 2px}.s{color:#5b6677;margin:0 0 16px}
.k{display:flex;gap:12px;flex-wrap:wrap;margin:14px 0}.c{border:1px solid #e6e9ef;border-radius:10px;padding:12px 16px}.c .n{font-size:24px;font-weight:700}.c .l{color:#5b6677;font-size:12px}
table{width:100%;border-collapse:collapse;border:1px solid #e6e9ef;border-radius:10px;overflow:hidden}
th,td{text-align:left;padding:9px 11px;border-bottom:1px solid #e6e9ef;vertical-align:top}
th{font-size:11px;text-transform:uppercase;color:#5b6677}.m{font-family:ui-monospace,Consolas,monospace;font-size:12px;color:#5b6677}
.w{color:#5b6677;font-size:12.5px;max-width:46ch}.b{padding:2px 9px;border-radius:999px;font-size:12px;font-weight:600}
.b.ok{background:#d9f0e4;color:#1a7f52}.b.ko{background:#f6dcde;color:#c23b45}.b.na{background:#e7eaef;color:#8893a4}
.ft{color:#5b6677;font-size:12px;margin-top:14px}</style></head><body>
<h1>Rapport d'audit (avant correction) — $($env:COMPUTERNAME)</h1>
<p class="s">$($report.OSDetail) · $($report.Utilisateur) · $(Get-Date -Format 'dd/MM/yyyy HH:mm') · duree de l'audit : $dur s</p>
<div class="k"><div class="c"><div class="n">$score%</div><div class="l">Conformite</div></div>
<div class="c"><div class="n">$nc</div><div class="l">Ecarts detectes</div></div>
<div class="c"><div class="n">$($applic.Count)</div><div class="l">Controles applicables</div></div></div>
<table><thead><tr><th>ID</th><th>Controle</th><th>Risque</th><th>Statut</th><th>Etat releve</th></tr></thead><tbody>
$rows
</tbody></table>
<p class="ft">Audit en lecture seule — aucune modification effectuee. Bahiri Consultant IT MSP Cybersecurite.</p>
</body></html>
"@
$html | Set-Content -Encoding UTF8 (Join-Path $OutDir 'rapport-poste.html')

Write-Host ("`nAudit termine en {0} s. {1} ecart(s) sur {2} controles applicables." -f $dur,$nc,$applic.Count) -ForegroundColor Yellow
Write-Host ("Rapport du poste : {0}" -f $OutDir) -ForegroundColor Green
Start-Process (Join-Path $OutDir 'rapport-poste.html')

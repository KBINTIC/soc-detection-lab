<#
  Audit-Poste-Windows.ps1  -  AUDIT EN LECTURE SEULE d'un poste Windows.
  Ne modifie RIEN. Produit un rapport JSON (schema commun PC/Mac) dans .\rapports\.
  Les identifiants de contrôle (FW-001, LLMNR-001...) sont alignés sur la suite de
  durcissement : une correction se valide d'abord en lab (VM) puis s'applique au poste.

  Usage (poste du client, PowerShell administrateur) :
     Set-ExecutionPolicy -Scope Process Bypass -Force ; .\Audit-Poste-Windows.ps1
  Ou double-cliquer sur  Lancer-Audit-Windows.bat
#>
param([string]$Client = '', [string]$OutDir = "$PSScriptRoot\rapports")

$ErrorActionPreference = 'Stop'
$debut = Get-Date
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force $OutDir | Out-Null }

function Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Admin)) { Write-Host "Lancez ce script dans un PowerShell ADMINISTRATEUR." -ForegroundColor Red; exit 1 }

# --- Catalogue des contrôles (audit seul : chaque bloc renvoie Statut + Actuel) ---
$controles = @(
  @{ Id='FW-001'; Cat='Pare-feu'; Risque='Haut'; Titre='Pare-feu Windows actif sur les trois profils'
     Pourquoi="Première barrière contre les connexions non sollicitées (vers partagés, mouvement latéral)."
     Correction='Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True'
     Check={ $off=@(Get-NetFirewallProfile|?{$_.Enabled -eq $false}); if($off.Count -eq 0){@{S='Conforme';A='Domain/Private/Public actifs'}}else{@{S='NonConforme';A=('Désactivé: '+($off.Name -join ', '))}} } },
  @{ Id='AV-001'; Cat='Antivirus/EDR'; Risque='Haut'; Titre='Protection antivirus temps réel active'
     Pourquoi="Sans temps réel, un fichier malveillant n'est analysé qu'à la demande. EDR tiers (GravityZone) => Defender passif (N/A)."
     Correction='Set-MpPreference -DisableRealtimeMonitoring $false'
     Check={ try{$m=Get-MpComputerStatus -ErrorAction Stop; if($m.AMRunningMode -eq 'Passive mode'){@{S='NA';A='Defender passif (EDR tiers)'}}elseif($m.RealTimeProtectionEnabled){@{S='Conforme';A='Temps réel actif'}}else{@{S='NonConforme';A='Temps réel désactivé'}} }catch{@{S='NA';A='Defender absent/remplacé'}} } },
  @{ Id='SMB-001'; Cat='Protocoles'; Risque='Haut'; Titre='SMBv1 désactivé'
     Pourquoi="SMBv1 est obsolète et vulnérable (EternalBlue/WannaCry). Aucun usage moderne."
     Correction='Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart'
     Check={ $f=Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue; if(-not $f -or $f.State -ne 'Enabled'){@{S='Conforme';A='SMBv1 absent/désactivé'}}else{@{S='NonConforme';A='SMBv1 activé'}} } },
  @{ Id='LLMNR-001'; Cat='Protocoles'; Risque='Moyen'; Titre='LLMNR désactivé'
     Pourquoi="LLMNR permet une résolution en diffusion détournée (Responder) pour capturer des identifiants."
     Correction='New-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Force; New-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name EnableMulticast -Value 0 -PropertyType DWord -Force'
     Check={ $v=Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Name EnableMulticast -ErrorAction SilentlyContinue; if($v -and $v.EnableMulticast -eq 0){@{S='Conforme';A='EnableMulticast=0'}}else{@{S='NonConforme';A='LLMNR actif'}} } },
  @{ Id='NTLM-001'; Cat='Authentification'; Risque='Moyen'; Titre='NTLMv2 imposé (LmCompatibilityLevel=5)'
     Pourquoi="Les anciens LM/NTLMv1 sont faciles à rejouer ou casser. Le niveau 5 n'accepte que NTLMv2."
     Correction='Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name LmCompatibilityLevel -Value 5 -Type DWord'
     Check={ $v=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name LmCompatibilityLevel -ErrorAction SilentlyContinue; if($v -and $v.LmCompatibilityLevel -ge 5){@{S='Conforme';A="Niveau $($v.LmCompatibilityLevel)"}}else{@{S='NonConforme';A='Niveau < 5 ou non défini'}} } },
  @{ Id='RDP-001'; Cat='Accès distant'; Risque='Moyen'; Titre='Si RDP actif, NLA exigé'
     Pourquoi="NLA oblige à s'authentifier avant d'ouvrir la session RDP. Sans objet si RDP désactivé."
     Correction='Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name UserAuthentication -Value 1 -Type DWord'
     Check={ $d=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -ErrorAction SilentlyContinue).fDenyTSConnections; if($d -ne 0){@{S='NA';A='RDP désactivé'}}else{$n=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -ErrorAction SilentlyContinue).UserAuthentication; if($n -eq 1){@{S='Conforme';A='RDP actif, NLA exigé'}}else{@{S='NonConforme';A='RDP actif sans NLA'}}} } },
  @{ Id='GUEST-001'; Cat='Comptes'; Risque='Moyen'; Titre='Compte invité désactivé'
     Pourquoi="Un compte invité actif offre un accès anonyme sans traçabilité."
     Correction='Get-LocalUser | Where-Object { $_.SID.Value -like "*-501" } | Disable-LocalUser'
     Check={ $g=Get-LocalUser|?{$_.SID.Value -like '*-501'}; if(-not $g){@{S='NA';A='Invité introuvable'}}elseif(-not $g.Enabled){@{S='Conforme';A='Invité désactivé'}}else{@{S='NonConforme';A='Invité ACTIF'}} } },
  @{ Id='BITLOCKER-001'; Cat='Chiffrement'; Risque='Haut'; Titre='Chiffrement BitLocker du disque système'
     Pourquoi="Sans chiffrement, un vol de poste donne accès aux données en retirant le disque."
     Correction='(manuel) Activer BitLocker + sauvegarder la clé de récupération'
     Check={ try{$b=Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop; if($b.ProtectionStatus -eq 'On'){@{S='Conforme';A='BitLocker actif'}}else{@{S='NonConforme';A="Inactif ($($b.VolumeStatus))"}} }catch{@{S='NonConforme';A='BitLocker indisponible'}} } },
  @{ Id='PSLOG-001'; Cat='Journalisation'; Risque='Moyen'; Titre='Journalisation des blocs de script PowerShell'
     Pourquoi="Enregistre le code PowerShell réellement exécuté, essentiel pour détecter les attaques par script."
     Correction='New-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -Force; New-ItemProperty ... EnableScriptBlockLogging 1 DWord'
     Check={ $v=Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' -Name EnableScriptBlockLogging -ErrorAction SilentlyContinue; if($v -and $v.EnableScriptBlockLogging -eq 1){@{S='Conforme';A='Activée'}}else{@{S='NonConforme';A='Désactivée'}} } },
  @{ Id='UPDATE-001'; Cat='Mises à jour'; Risque='Haut'; Titre='Mises à jour Windows récentes (< 45 jours)'
     Pourquoi="Un poste non à jour cumule des vulnérabilités connues et exploitées."
     Correction='(manuel/WSUS) Lancer Windows Update et planifier les mises à jour'
     Check={ try{$h=Get-HotFix|Sort-Object InstalledOn -Descending|Select-Object -First 1; if($h -and $h.InstalledOn -gt (Get-Date).AddDays(-45)){@{S='Conforme';A="Dernier correctif: $($h.InstalledOn.ToString('yyyy-MM-dd'))"}}else{@{S='NonConforme';A='Aucun correctif récent (>45j)'}} }catch{@{S='NA';A='Historique indisponible'}} } }
)

Write-Host "`n=== Audit (lecture seule) - $env:COMPUTERNAME ===" -ForegroundColor Cyan
$res = foreach ($c in $controles) {
  $r = & $c.Check
  $icon = switch ($r.S) {'Conforme'{'[OK]'} 'NonConforme'{'[!!]'} default {'[--]'}}
  $col  = switch ($r.S) {'Conforme'{'Green'} 'NonConforme'{'Red'} default {'DarkGray'}}
  Write-Host ("  {0} {1,-12} {2}" -f $icon,$c.Id,$c.Titre) -ForegroundColor $col
  [pscustomobject]@{ id=$c.Id; titre=$c.Titre; categorie=$c.Cat; risque=$c.Risque; pourquoi=$c.Pourquoi
                     statut=$r.S; actuel=$r.A; correction=$c.Correction }
}

$fin = Get-Date
$conf=@($res|?{$_.statut -eq 'Conforme'}).Count
$nc  =@($res|?{$_.statut -eq 'NonConforme'}).Count
$na  =@($res|?{$_.statut -eq 'NA'}).Count
$appl=$conf+$nc
$score= if($appl -gt 0){[math]::Round(100*$conf/$appl)}else{0}

$rapport = [ordered]@{
  client        = $Client
  poste         = $env:COMPUTERNAME
  type          = 'PC'
  os            = (Get-CimInstance Win32_OperatingSystem).Caption
  utilisateur   = "$env:USERDOMAIN\$env:USERNAME"
  horodatage    = $debut.ToString('o')
  duree_secondes= [int]([math]::Round(($fin-$debut).TotalSeconds))
  score         = $score
  conformes     = $conf; non_conformes=$nc; non_applicable=$na
  controles     = $res
}
$stamp = $debut.ToString('yyyyMMdd-HHmmss')
$path  = Join-Path $OutDir ("rapport-PC-{0}-{1}.json" -f $env:COMPUTERNAME,$stamp)
$rapport | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $path

Write-Host ("`nDurée: {0}s  |  Score: {1}%  |  Écarts: {2}" -f $rapport.duree_secondes,$score,$nc) -ForegroundColor Yellow
Write-Host "Rapport JSON: $path" -ForegroundColor Green
Write-Host "Rapatriez le dossier 'rapports' sur le Mac, puis générez le rapport PDF." -ForegroundColor Cyan

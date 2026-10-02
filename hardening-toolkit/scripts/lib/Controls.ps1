# =====================================================================
#  Controls.ps1 - catalogue des contrôles de sécurité du poste Windows
#  Chaque contrôle est autonome : il sait se vérifier, se corriger et s'annuler.
#  Référentiel : bonnes pratiques ANSSI / CIS pour postes TPE/PME.
#
#  Champs d'un contrôle :
#   Id         identifiant court et stable
#   Titre      libellé lisible
#   Pourquoi   l'intérêt défensif, affiché AVANT toute correction
#   Risque     Haut | Moyen | Bas
#   Categorie  regroupement pour le rapport
#   Verifier   scriptblock -> renvoie @{ Statut='Conforme|NonConforme|NA'; Actuel=<texte> }
#   Corriger   scriptblock qui applique le durcissement (idempotent)
#   Undo       texte PowerShell d'annulation (rejoué par 99-Undo.ps1)
# =====================================================================

function Get-SecurityControls {
    @(
        [pscustomobject]@{
            Id='FW-001'; Categorie='Pare-feu'; Risque='Haut'
            Titre='Pare-feu Windows actif sur les trois profils'
            Pourquoi="Le pare-feu est la première barrière contre les connexions non sollicitées (vers partagés, mouvement latéral). Un profil désactivé laisse une porte ouverte sur ce réseau."
            Verifier={
                $off = @(Get-NetFirewallProfile | Where-Object Enabled -eq $false)
                if ($off.Count -eq 0) { @{Statut='Conforme';Actuel='Domain/Private/Public : actifs'} }
                else { @{Statut='NonConforme';Actuel=("Désactivé : " + ($off.Name -join ', '))} }
            }
            Corriger={ Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True }
            Undo='# Réactiver seulement si vous aviez une raison de le couper :' + "`n" +
                 '# Set-NetFirewallProfile -Profile Public -Enabled False'
        },
        [pscustomobject]@{
            Id='AV-001'; Categorie='Antivirus / EDR'; Risque='Haut'
            Titre='Protection en temps réel active'
            Pourquoi="Sans protection temps réel, un fichier malveillant n'est analysé qu'à la demande, trop tard. Sur un poste sous EDR tiers (GravityZone), Defender passe en mode passif : ce contrôle est alors non applicable."
            Verifier={
                try {
                    $mp = Get-MpComputerStatus -ErrorAction Stop
                    if ($mp.AMRunningMode -eq 'Passive mode') { @{Statut='NA';Actuel='Defender passif (EDR tiers présent)'} }
                    elseif ($mp.RealTimeProtectionEnabled) { @{Statut='Conforme';Actuel='Temps réel actif'} }
                    else { @{Statut='NonConforme';Actuel='Temps réel désactivé'} }
                } catch { @{Statut='NA';Actuel='Defender absent ou remplacé par un EDR tiers'} }
            }
            Corriger={ Set-MpPreference -DisableRealtimeMonitoring $false }
            Undo='# (non recommandé) Set-MpPreference -DisableRealtimeMonitoring $true'
        },
        [pscustomobject]@{
            Id='SMB-001'; Categorie='Protocoles réseau'; Risque='Haut'
            Titre='SMBv1 désactivé'
            Pourquoi="SMBv1 est obsolète et vulnérable (WannaCry/EternalBlue l'exploitaient). Aucun usage légitime moderne ne le nécessite sur un poste."
            Verifier={
                $f = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue
                if (-not $f -or $f.State -ne 'Enabled') { @{Statut='Conforme';Actuel='SMBv1 absent/désactivé'} }
                else { @{Statut='NonConforme';Actuel='SMBv1 activé'} }
            }
            Corriger={ Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart | Out-Null }
            Undo='Enable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart'
        },
        [pscustomobject]@{
            Id='LLMNR-001'; Categorie='Protocoles réseau'; Risque='Moyen'
            Titre='LLMNR désactivé'
            Pourquoi="LLMNR permet une résolution de noms en diffusion qu'un attaquant local détourne (Responder) pour capturer des identifiants. On le désactive au profit du DNS."
            Verifier={
                $v = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Name EnableMulticast -ErrorAction SilentlyContinue
                if ($v -and $v.EnableMulticast -eq 0) { @{Statut='Conforme';Actuel='EnableMulticast=0'} }
                else { @{Statut='NonConforme';Actuel='LLMNR actif (valeur absente ou =1)'} }
            }
            Corriger={
                New-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Force | Out-Null
                New-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Name EnableMulticast -Value 0 -PropertyType DWord -Force | Out-Null
            }
            Undo='Remove-ItemProperty ''HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'' -Name EnableMulticast -ErrorAction SilentlyContinue'
        },
        [pscustomobject]@{
            Id='NTLM-001'; Categorie='Authentification'; Risque='Moyen'
            Titre='NTLMv2 imposé (LmCompatibilityLevel = 5)'
            Pourquoi="Les anciens LM/NTLMv1 ont des empreintes faciles à rejouer ou à casser. Le niveau 5 refuse LM et NTLMv1 et n'accepte que NTLMv2."
            Verifier={
                $v = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name LmCompatibilityLevel -ErrorAction SilentlyContinue
                if ($v -and $v.LmCompatibilityLevel -ge 5) { @{Statut='Conforme';Actuel="Niveau $($v.LmCompatibilityLevel)"} }
                else { @{Statut='NonConforme';Actuel=("Niveau " + ($(if($v){$v.LmCompatibilityLevel}else{'non défini'})))} }
            }
            Corriger={ Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name LmCompatibilityLevel -Value 5 -Type DWord }
            Undo='Remove-ItemProperty ''HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'' -Name LmCompatibilityLevel -ErrorAction SilentlyContinue'
        },
        [pscustomobject]@{
            Id='RDP-001'; Categorie='Accès distant'; Risque='Moyen'
            Titre="Si RDP est actif, l'authentification NLA est exigée"
            Pourquoi="NLA (Network Level Authentication) oblige à s'authentifier avant d'ouvrir une session RDP, ce qui réduit l'exposition aux attaques pré-authentification. Si RDP est désactivé, le contrôle est sans objet."
            Verifier={
                $deny = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -ErrorAction SilentlyContinue).fDenyTSConnections
                if ($deny -ne 0) { @{Statut='NA';Actuel='RDP désactivé'} }
                else {
                    $nla = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -ErrorAction SilentlyContinue).UserAuthentication
                    if ($nla -eq 1) { @{Statut='Conforme';Actuel='RDP actif, NLA exigé'} }
                    else { @{Statut='NonConforme';Actuel='RDP actif sans NLA'} }
                }
            }
            Corriger={ Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -Value 1 -Type DWord }
            Undo='Set-ItemProperty ''HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'' -Name UserAuthentication -Value 0 -Type DWord'
        },
        [pscustomobject]@{
            Id='GUEST-001'; Categorie='Comptes'; Risque='Moyen'
            Titre='Compte invité désactivé'
            Pourquoi="Un compte invité actif offre un accès anonyme sans traçabilité. Il doit rester désactivé."
            Verifier={
                $g = Get-LocalUser | Where-Object { $_.SID.Value -like '*-501' }
                if (-not $g) { @{Statut='NA';Actuel='Compte invité introuvable'} }
                elseif (-not $g.Enabled) { @{Statut='Conforme';Actuel='Invité désactivé'} }
                else { @{Statut='NonConforme';Actuel='Invité ACTIF'} }
            }
            Corriger={ Get-LocalUser | Where-Object { $_.SID.Value -like '*-501' } | Disable-LocalUser }
            Undo='# Get-LocalUser | Where-Object { $_.SID.Value -like ''*-501'' } | Enable-LocalUser'
        },
        [pscustomobject]@{
            Id='BITLOCKER-001'; Categorie='Chiffrement'; Risque='Haut'
            Titre='Chiffrement BitLocker du disque système'
            Pourquoi="Sans chiffrement, un vol de portable donne accès à toutes les données en retirant le disque. BitLocker protège les données au repos. (Contrôle en lecture seule : l'activation n'est pas automatisée car elle nécessite une décision et une sauvegarde de clé.)"
            Verifier={
                try {
                    $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
                    if ($bl.ProtectionStatus -eq 'On') { @{Statut='Conforme';Actuel='BitLocker actif'} }
                    else { @{Statut='NonConforme';Actuel="BitLocker inactif ($($bl.VolumeStatus))"} }
                } catch { @{Statut='NonConforme';Actuel='BitLocker indisponible'} }
            }
            Corriger=$null   # volontairement non automatisé
            Undo=$null
        },
        [pscustomobject]@{
            Id='PSLOG-001'; Categorie='Journalisation'; Risque='Moyen'
            Titre='Journalisation des blocs de script PowerShell'
            Pourquoi="Elle enregistre le code PowerShell réellement exécuté, y compris désobfusqué. C'est une source essentielle pour détecter et investiguer les attaques par script (cf. ta règle 'PowerShell encodé')."
            Verifier={
                $v = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' -Name EnableScriptBlockLogging -ErrorAction SilentlyContinue
                if ($v -and $v.EnableScriptBlockLogging -eq 1) { @{Statut='Conforme';Actuel='Activée'} }
                else { @{Statut='NonConforme';Actuel='Désactivée'} }
            }
            Corriger={
                New-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' -Force | Out-Null
                New-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' -Name EnableScriptBlockLogging -Value 1 -PropertyType DWord -Force | Out-Null
            }
            Undo='Remove-ItemProperty ''HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'' -Name EnableScriptBlockLogging -ErrorAction SilentlyContinue'
        },
        [pscustomobject]@{
            Id='AUDIT-001'; Categorie='Journalisation'; Risque='Moyen'
            Titre='Audit de la gestion des comptes et des groupes'
            Pourquoi="Sans cet audit, l'ajout d'un compte au groupe Administrateurs (event 4732) n'est pas journalisé, et la détection correspondante reste aveugle."
            Verifier={
                $out = & auditpol /get /subcategory:"{0CCE9237-69AE-11D9-BED3-505054503030}" 2>$null
                if ($out -match 'Succ') { @{Statut='Conforme';Actuel='Audit succès activé'} }
                else { @{Statut='NonConforme';Actuel='Audit désactivé'} }
            }
            Corriger={ & auditpol /set /subcategory:"{0CCE9237-69AE-11D9-BED3-505054503030}" /success:enable /failure:enable | Out-Null }
            Undo='auditpol /set /subcategory:"{0CCE9237-69AE-11D9-BED3-505054503030}" /success:disable /failure:disable'
        }
    )
}

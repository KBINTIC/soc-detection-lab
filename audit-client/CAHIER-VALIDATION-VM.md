# Cahier de validation des corrections (sur ta VM, AVANT application client)

L'audit ne corrige rien. Avant d'appliquer une correction sur le poste d'un client, **tu la valides
sur ta VM de lab** : tu exécutes la commande, tu relances l'audit, tu vérifies que l'écart passe au vert,
et tu contrôles qu'aucun usage légitime n'est cassé. Chaque correction a une commande d'**annulation**.

Procédure pour chaque écart :
1. Sur la VM, relève l'état initial (lance l'audit du kit, ou la commande de vérification ci-dessous).
2. Exécute la **commande de correction** dans un terminal **administrateur** (PowerShell élevé sur Windows, `sudo` sur Mac).
3. Relance l'audit : l'écart doit passer **Conforme**.
4. Vérifie l'usage (réseau, partage, connexion…). Si quelque chose casse, applique l'**annulation**.
5. Seulement alors, planifie la correction chez le client (via `hardening-toolkit`, avec validation O/N).

---

## Windows (PowerShell administrateur)

| ID | Correction | Annulation |
|---|---|---|
| **FW-001** Pare-feu | `Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True` | `Set-NetFirewallProfile -Profile Public -Enabled False` (seulement si justifié) |
| **AV-001** Temps réel | `Set-MpPreference -DisableRealtimeMonitoring $false` | `Set-MpPreference -DisableRealtimeMonitoring $true` (déconseillé) |
| **SMB-001** SMBv1 | `Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart` | `Enable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart` |
| **LLMNR-001** | `New-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Force; New-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Name EnableMulticast -Value 0 -PropertyType DWord -Force` | `Remove-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Name EnableMulticast` |
| **NTLM-001** | `Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name LmCompatibilityLevel -Value 5 -Type DWord` | `Remove-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name LmCompatibilityLevel` |
| **RDP-001** NLA | `Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -Value 1 -Type DWord` | `... -Value 0` |
| **GUEST-001** | `Get-LocalUser | Where-Object { $_.SID.Value -like '*-501' } | Disable-LocalUser` | `... | Enable-LocalUser` |
| **BITLOCKER-001** | **Non automatisé** : activer BitLocker avec le client, **sauvegarder la clé de récupération** (AD/Entra ou impression). | `Disable-BitLocker -MountPoint C:` |
| **UPDATE-001** | Lancer Windows Update ; vérifier le service `wuauserv` et la stratégie de MAJ. | — |
| **PSLOG-001** | `New-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' -Force; New-ItemProperty ... -Name EnableScriptBlockLogging -Value 1 -PropertyType DWord -Force` | `Remove-ItemProperty ... -Name EnableScriptBlockLogging` |

Points de vérification d'usage : après **SMB-001** et **NTLM-001**, teste l'accès aux partages réseau et aux
imprimantes partagées. Après **FW-001**, teste les applications métier qui écoutent sur le réseau. Un **redémarrage**
peut être nécessaire pour SMBv1 et NTLM.

---

## Mac (Terminal, avec `sudo`)

| ID | Correction | Annulation |
|---|---|---|
| **FW-001** Pare-feu | `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on` | `... --setglobalstate off` |
| **FW-002** Mode furtif | `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on` | `... --setstealthmode off` |
| **FV-001** FileVault | **Avec le client** : `sudo fdesetup enable` puis **conserver la clé de récupération** affichée. | `sudo fdesetup disable` |
| **GK-001** Gatekeeper | `sudo spctl --master-enable` | `sudo spctl --master-disable` |
| **SIP-001** | Se corrige **depuis la Récupération** (`csrutil enable`), pas en session normale. | `csrutil disable` (Récupération) |
| **UPD-001** MAJ auto | `sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true` | `... -bool false` |
| **SSH-001** SSH | `sudo systemsetup -setremotelogin off` | `sudo systemsetup -setremotelogin on` |
| **SHARE-001** Partage d'écran | Réglages Système > Général > Partage > **désactiver** Partage d'écran / Gestion à distance. | réactiver au même endroit |
| **SMB-001** Partage fichiers | Réglages Système > Général > Partage > **désactiver** Partage de fichiers. | réactiver au même endroit |
| **GUEST-001** Invité | `sudo sysadminctl -guestAccount off` | `sudo sysadminctl -guestAccount on` |

Points de vérification d'usage : après **FW/SSH/partages**, confirme avec le client qu'aucun flux légitime
(sauvegarde réseau, prise en main à distance, partage d'imprimante) n'est interrompu. **FileVault** et **SIP**
exigent une décision explicite du client et une sauvegarde de clé : ne jamais les activer à la volée.

---

**Règle d'or** : une correction non validée sur la VM ne part jamais chez un client.

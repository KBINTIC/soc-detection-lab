<#
  00-Simulate-Benign.ps1
  BUT : générer des événements de sécurité INOFFENSIFS et RÉVERSIBLES, pour
        vérifier que la collecte (Sysmon + agent Wazuh/EDR) et les règles de
        détection fonctionnent AVANT de toucher à la configuration.
  Ne modifie rien durablement : chaque action est immédiatement annulée.
  À lancer dans un PowerShell administrateur, uniquement sur une machine de LAB.
#>
. "$PSScriptRoot\lib\Common.ps1"
Test-Admin
Write-Title "Simulation bénigne (lab uniquement)"
Write-Line "Chaque test génère un événement observable puis revient à l'état initial.`n" 'Yellow'

$tests = @(
  @{ Nom='Journal de sécurité effacé (1102)';      Action={ wevtutil cl Security } },
  @{ Nom='PowerShell encodé (Sysmon 1)';           Action={ powershell.exe -enc VwByAGkAdABlAC0ASABvAHMAdAAgACIAcwBpAGcAbQBhACAAbABhAGIAIAB0AGUAcwB0ACIA | Out-Null } },
  @{ Nom='Ajout puis retrait au groupe Admins (4732)'; Action={
        net user _labtest 'L@b-Only-2026!' /add | Out-Null
        Add-LocalGroupMember   -SID 'S-1-5-32-544' -Member _labtest -ErrorAction SilentlyContinue
        Remove-LocalGroupMember -SID 'S-1-5-32-544' -Member _labtest -ErrorAction SilentlyContinue
        net user _labtest /delete | Out-Null } },
  @{ Nom='LLMNR réactivé puis re-durci (Sysmon 13)'; Action={
        $k='HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
        New-Item $k -Force | Out-Null
        New-ItemProperty $k -Name EnableMulticast -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty $k -Name EnableMulticast -Value 0 -PropertyType DWord -Force | Out-Null } }
)

foreach ($t in $tests) {
  Write-Host ("  • {0}" -f $t.Nom) -NoNewline
  try { & $t.Action; Write-Host "  -> généré" -ForegroundColor Green }
  catch { Write-Host "  -> échec : $($_.Exception.Message)" -ForegroundColor Red }
}

Write-Line "`nTermine. Vérifie dans ton SIEM que les 4 événements apparaissent (voir docs/detections.md)." 'Cyan'

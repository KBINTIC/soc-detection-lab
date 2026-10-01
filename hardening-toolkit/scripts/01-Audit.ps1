<#
  01-Audit.ps1
  BUT : auditer la configuration de sécurité du poste SANS RIEN MODIFIER.
        Produit un rapport JSON (phase 'avant' par défaut) dans reports\.
  Usage :
     .\01-Audit.ps1                 # rapport 'avant' (état initial)
     .\01-Audit.ps1 -Phase apres    # rapport 'apres' (après durcissement)
#>
param([ValidateSet('avant','apres')][string]$Phase = 'avant')

. "$PSScriptRoot\lib\Common.ps1"
. "$PSScriptRoot\lib\Controls.ps1"
Test-Admin

Write-Title "Audit de sécurité - phase '$Phase' - $env:COMPUTERNAME"
$controls = Get-SecurityControls
$results  = foreach ($c in $controls) {
    $r = & $c.Verifier
    $icon = switch ($r.Statut) { 'Conforme'{'[OK]'} 'NonConforme'{'[!!]'} default {'[--]'} }
    $color= switch ($r.Statut) { 'Conforme'{'Green'} 'NonConforme'{'Red'} default {'DarkGray'} }
    Write-Host ("  {0} {1,-9} {2}" -f $icon, $c.Id, $c.Titre) -ForegroundColor $color
    Write-Host ("        état : {0}" -f $r.Actuel) -ForegroundColor DarkGray
    [pscustomobject]@{
        Id=$c.Id; Titre=$c.Titre; Categorie=$c.Categorie; Risque=$c.Risque
        Pourquoi=$c.Pourquoi; Statut=$r.Statut; Actuel=$r.Actuel
        Corrigeable = [bool]$c.Corriger
    }
}

$path = Export-Report -Checks $results -Phase $Phase
$nc = @($results | Where-Object Statut -eq 'NonConforme').Count
Write-Line ("`nRésumé : {0} non conforme(s) sur {1} contrôles applicables." -f $nc, @($results | Where-Object Statut -ne 'NA').Count) 'Yellow'
if ($Phase -eq 'avant' -and $nc -gt 0) { Write-Line "Pour corriger : .\02-Harden.ps1" 'Cyan' }

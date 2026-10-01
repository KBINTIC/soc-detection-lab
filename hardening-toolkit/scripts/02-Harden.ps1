<#
  02-Harden.ps1
  BUT : appliquer le durcissement, contrôle par contrôle.
        Pour chaque écart, le script explique le POURQUOI, puis demande O/N :
        la machine exécute, l'humain décide. Chaque correction appliquée est
        enregistrée dans le journal d'annulation (reports\undo-<machine>.json).
  Usage :
     .\02-Harden.ps1            # mode interactif (demande O/N à chaque fois)
     .\02-Harden.ps1 -Auto      # applique tout sans demander (à réserver au lab)
     .\02-Harden.ps1 -WhatIf    # montre ce qui serait fait, sans rien changer
#>
param([switch]$Auto, [switch]$WhatIf)

. "$PSScriptRoot\lib\Common.ps1"
. "$PSScriptRoot\lib\Controls.ps1"
Test-Admin

Write-Title "Durcissement - $env:COMPUTERNAME"
Write-Line "La machine exécute, l'humain décide. Répondez O (oui), N (non), ou A (tout le reste)." 'Yellow'

$applyAll = $Auto
foreach ($c in Get-SecurityControls) {
    $r = & $c.Verifier
    if ($r.Statut -ne 'NonConforme') { continue }           # déjà conforme ou non applicable
    if (-not $c.Corriger) {
        Write-Host "`n[$($c.Id)] $($c.Titre)" -ForegroundColor Yellow
        Write-Host "   -> correction manuelle requise (non automatisée)." -ForegroundColor DarkYellow
        Write-Host "   Pourquoi : $($c.Pourquoi)" -ForegroundColor Gray
        continue
    }

    Write-Host "`n[$($c.Id)] $($c.Titre)   (risque : $($c.Risque))" -ForegroundColor Cyan
    Write-Host "   État actuel : $($r.Actuel)" -ForegroundColor DarkGray
    Write-Host "   Pourquoi    : $($c.Pourquoi)" -ForegroundColor Gray

    if ($WhatIf) { Write-Host "   [WhatIf] correction non appliquée." -ForegroundColor DarkGray; continue }

    $do = $applyAll
    if (-not $do) {
        $ans = Read-Host "   Appliquer la correction ? (O/N/A)"
        if ($ans -match '^[Aa]') { $applyAll = $true; $do = $true }
        elseif ($ans -match '^[Oo]') { $do = $true }
    }
    if (-not $do) { Write-Host "   -> ignoré." -ForegroundColor DarkGray; continue }

    try {
        & $c.Corriger
        Add-UndoEntry $c
        $after = & $c.Verifier
        if ($after.Statut -eq 'Conforme') { Write-Host "   -> corrigé." -ForegroundColor Green }
        else { Write-Host "   -> appliqué, mais toujours '$($after.Statut)' (redémarrage requis ?)." -ForegroundColor Yellow }
    } catch { Write-Host "   -> échec : $($_.Exception.Message)" -ForegroundColor Red }
}

Write-Line "`nDurcissement terminé. Journal d'annulation : $UndoJournal" 'Cyan'
Write-Line "Étape suivante : .\01-Audit.ps1 -Phase apres   puis   .\03-Report.ps1" 'Cyan'

<#
  99-Undo.ps1
  BUT : annuler les corrections appliquées par 02-Harden.ps1, en rejouant
        les commandes d'annulation enregistrées dans le journal undo.
        On revient en arrière dans l'ordre inverse des corrections.
  Usage :
     .\99-Undo.ps1            # interactif : demande confirmation par entrée
     .\99-Undo.ps1 -Auto      # annule tout sans demander
#>
param([switch]$Auto)

. "$PSScriptRoot\lib\Common.ps1"
Test-Admin

if (-not (Test-Path $UndoJournal)) { Write-Line "Aucun journal d'annulation : rien à annuler." 'Yellow'; return }
$entries = @(Get-Content $UndoJournal -Raw | ConvertFrom-Json)
[array]::Reverse($entries)

Write-Title "Annulation des corrections ($($entries.Count) entrée(s))"
foreach ($e in $entries) {
    if (-not $e.Undo -or $e.Undo -match '^\s*#') {
        Write-Host "[$($e.Id)] $($e.Titre) : pas d'annulation automatique." -ForegroundColor DarkGray
        continue
    }
    Write-Host "`n[$($e.Id)] $($e.Titre)" -ForegroundColor Cyan
    Write-Host "   Commande : $($e.Undo)" -ForegroundColor DarkGray
    $do = $Auto
    if (-not $do) { $do = (Read-Host "   Annuler cette correction ? (O/N)") -match '^[Oo]' }
    if (-not $do) { Write-Host "   -> conservé." -ForegroundColor DarkGray; continue }
    try { Invoke-Expression $e.Undo; Write-Host "   -> annulé." -ForegroundColor Green }
    catch { Write-Host "   -> échec : $($_.Exception.Message)" -ForegroundColor Red }
}
Write-Line "`nAnnulation terminée. Relancez .\01-Audit.ps1 pour vérifier l'état." 'Cyan'

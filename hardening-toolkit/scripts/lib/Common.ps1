# =====================================================================
#  Common.ps1 - bibliothèque partagée de la suite d'audit / durcissement
#  Principe : la machine exécute, l'humain décide.
#  Chargé par les autres scripts via :  . "$PSScriptRoot\lib\Common.ps1"
# =====================================================================

$script:LabRoot    = Split-Path -Parent (Split-Path -Parent $PSCommandPath)   # racine du toolkit
$script:ReportsDir = Join-Path $LabRoot 'reports'
if (-not (Test-Path $ReportsDir)) { New-Item -ItemType Directory -Force $ReportsDir | Out-Null }

function Write-Line($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }
function Write-Title($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Ce script doit être lancé dans un PowerShell en tant qu'administrateur."
    }
}

# Nom horodaté d'un rapport : audit-<phase>-<machine>-<date>.json
function Get-ReportPath([string]$Phase) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Join-Path $ReportsDir ("audit-{0}-{1}-{2}.json" -f $Phase, $env:COMPUTERNAME, $stamp)
}

# Journal d'annulation (undo) : une ligne par correction appliquée
$script:UndoJournal = Join-Path $ReportsDir ("undo-{0}.json" -f $env:COMPUTERNAME)

function Add-UndoEntry($Check) {
    $entry = [pscustomobject]@{
        Horodatage = (Get-Date).ToString('o')
        Id         = $Check.Id
        Titre      = $Check.Titre
        Undo       = $Check.Undo      # texte de la commande d'annulation
    }
    $all = @()
    if (Test-Path $UndoJournal) { $all = @(Get-Content $UndoJournal -Raw | ConvertFrom-Json) }
    $all += $entry
    $all | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $UndoJournal
}

# Exporte la liste des contrôles évalués vers un rapport JSON et renvoie son chemin.
function Export-Report {
    param([array]$Checks, [string]$Phase)
    $conformes    = @($Checks | Where-Object Statut -eq 'Conforme').Count
    $nonConformes = @($Checks | Where-Object Statut -eq 'NonConforme').Count
    $na           = @($Checks | Where-Object Statut -eq 'NA').Count
    $total        = $conformes + $nonConformes
    $score        = if ($total -gt 0) { [math]::Round(100 * $conformes / $total) } else { 0 }

    $report = [pscustomobject]@{
        Machine      = $env:COMPUTERNAME
        Utilisateur  = "$env:USERDOMAIN\$env:USERNAME"
        OS           = (Get-CimInstance Win32_OperatingSystem).Caption
        Phase        = $Phase          # 'avant' ou 'apres'
        Horodatage   = (Get-Date).ToString('o')
        Score        = $score
        Conformes    = $conformes
        NonConformes = $nonConformes
        NonApplicable= $na
        Controles    = $Checks
    }
    $path = Get-ReportPath $Phase
    $report | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $path
    Write-Line "Rapport $Phase écrit : $path" 'Green'
    return $path
}

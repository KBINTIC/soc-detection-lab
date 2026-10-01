<#
  03-Report.ps1
  BUT : produire un rapport HTML AVANT / APRÈS autonome à partir des deux
        derniers rapports JSON (phase 'avant' et phase 'apres') de reports\.
        Le rapport s'ouvre dans le navigateur ; il est partageable tel quel
        (un seul fichier, aucune dépendance externe).
  Usage :
     .\03-Report.ps1            # prend les derniers rapports avant/apres
#>
. "$PSScriptRoot\lib\Common.ps1"

function Get-Latest($phase) {
    Get-ChildItem $ReportsDir -Filter "audit-$phase-*.json" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
}
$avantFile = Get-Latest 'avant'
$apresFile = Get-Latest 'apres'
if (-not $avantFile) { Write-Line "Aucun rapport 'avant'. Lancez d'abord .\01-Audit.ps1" 'Red'; return }
$avant = Get-Content $avantFile.FullName -Raw | ConvertFrom-Json
$apres = if ($apresFile) { Get-Content $apresFile.FullName -Raw | ConvertFrom-Json } else { $null }

function Badge($s) {
    switch ($s) {
        'Conforme'    { '<span class="b ok">Conforme</span>' }
        'NonConforme' { '<span class="b ko">Non conforme</span>' }
        default       { '<span class="b na">N/A</span>' }
    }
}
$rows = foreach ($c in $avant.Controles) {
    $a = if ($apres) { ($apres.Controles | Where-Object Id -eq $c.Id) } else { $null }
    $apColHtml = if ($apres) { "<td>$(Badge ($a.Statut))</td>" } else { '' }
    $evol = ''
    if ($apres -and $c.Statut -eq 'NonConforme' -and $a.Statut -eq 'Conforme') { $evol=' class="fixed"' }
    "<tr$evol>
       <td class='mono'>$($c.Id)</td>
       <td>$($c.Titre)<div class='why'>$($c.Pourquoi)</div></td>
       <td>$($c.Risque)</td>
       <td>$(Badge $c.Statut)</td>
       $apColHtml
     </tr>"
}
$apHead = if ($apres) { '<th>Après</th>' } else { '' }
$scoreApres = if ($apres) { "$($apres.Score)%" } else { '—' }
$gen = Get-Date -Format 'dd/MM/yyyy HH:mm'

$html = @"
<!doctype html><html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Rapport de durcissement - $($avant.Machine)</title>
<style>
:root{--bg:#f6f7f9;--card:#fff;--ink:#1a2230;--mut:#5b6677;--line:#e6e9ef;--ok:#1a7f52;--ko:#c23b45;--na:#8893a4;--accent:#2f5bea}
@media(prefers-color-scheme:dark){:root:not([data-theme=light]){--bg:#0f141c;--card:#161d28;--ink:#e8ecf3;--mut:#9aa6b6;--line:#26303d;--ok:#4cc38a;--ko:#f06b73;--na:#7d8697;--accent:#6f92ff}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.55 -apple-system,Segoe UI,Roboto,sans-serif}
.wrap{max-width:1000px;margin:0 auto;padding:24px 16px}
h1{font-size:22px;margin:0 0 2px}.sub{color:var(--mut);margin:0 0 20px}
.cards{display:flex;gap:12px;flex-wrap:wrap;margin-bottom:20px}
.c{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px 18px;flex:1;min-width:150px}
.c .n{font-size:28px;font-weight:700}.c .l{color:var(--mut);font-size:13px}
table{width:100%;border-collapse:collapse;background:var(--card);border:1px solid var(--line);border-radius:12px;overflow:hidden}
th,td{text-align:left;padding:10px 12px;border-bottom:1px solid var(--line);vertical-align:top}
th{font-size:12px;text-transform:uppercase;letter-spacing:.04em;color:var(--mut)}
tr:last-child td{border-bottom:none}
.mono{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:13px;color:var(--mut)}
.why{color:var(--mut);font-size:12.5px;margin-top:4px;max-width:46ch}
.b{display:inline-block;padding:2px 9px;border-radius:999px;font-size:12px;font-weight:600;white-space:nowrap}
.b.ok{background:color-mix(in srgb,var(--ok) 16%,transparent);color:var(--ok)}
.b.ko{background:color-mix(in srgb,var(--ko) 16%,transparent);color:var(--ko)}
.b.na{background:color-mix(in srgb,var(--na) 16%,transparent);color:var(--na)}
tr.fixed{background:color-mix(in srgb,var(--ok) 7%,transparent)}
.ft{color:var(--mut);font-size:12px;margin-top:16px}
</style></head><body><div class="wrap">
<h1>Rapport de durcissement — $($avant.Machine)</h1>
<p class="sub">$($avant.OS) · $($avant.Utilisateur) · généré le $gen</p>
<div class="cards">
  <div class="c"><div class="n">$($avant.Score)%</div><div class="l">Conformité avant</div></div>
  <div class="c"><div class="n">$scoreApres</div><div class="l">Conformité après</div></div>
  <div class="c"><div class="n">$($avant.NonConformes)</div><div class="l">Écarts détectés (avant)</div></div>
</div>
<table><thead><tr><th>ID</th><th>Contrôle</th><th>Risque</th><th>Avant</th>$apHead</tr></thead>
<tbody>
$($rows -join "`n")
</tbody></table>
<p class="ft">Suite d'audit / durcissement — Bahiri Consultant IT MSP Cybersécurité. Chaque correction est réversible (99-Undo.ps1).</p>
</div></body></html>
"@

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $ReportsDir ("rapport-{0}-{1}.html" -f $env:COMPUTERNAME, $stamp)
$html | Set-Content -Encoding UTF8 $out
Write-Line "Rapport HTML : $out" 'Green'
Start-Process $out

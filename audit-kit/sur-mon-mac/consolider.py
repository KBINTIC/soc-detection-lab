#!/usr/bin/env python3
# consolider.py - agrege tous les rapports postes/*/audit.json en un rapport client.
# Usage : python3 consolider.py [dossier_postes] [nom_client]
import sys, os, json, glob, datetime, webbrowser, html

base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
postes_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(base, "postes")
client = sys.argv[2] if len(sys.argv) > 2 else "Client"

files = sorted(glob.glob(os.path.join(postes_dir, "*", "audit.json")))
if not files:
    print(f"Aucun rapport trouve dans {postes_dir}. Lancez d'abord les audits sur les postes.")
    sys.exit(1)

postes, durations = [], []
by_control = {}   # id -> {titre, risque, nc, total_applicable}
for f in files:
    try:
        d = json.load(open(f, encoding="utf-8"))
    except Exception as e:
        print(f"  (ignore {f}: {e})"); continue
    postes.append(d)
    durations.append(d.get("DureeSecondes", 0) or 0)
    for c in d.get("Controles", []):
        k = c["Id"]
        e = by_control.setdefault(k, {"titre": c["Titre"], "risque": c.get("Risque",""), "nc": 0, "appl": 0})
        if c["Statut"] == "NonConforme": e["nc"] += 1; e["appl"] += 1
        elif c["Statut"] == "Conforme": e["appl"] += 1

n = len(postes)
n_win = sum(1 for p in postes if p.get("Systeme") == "Windows")
n_mac = sum(1 for p in postes if p.get("Systeme") == "Mac")
avg_dur = round(sum(durations)/len(durations)) if durations else 0
avg_score = round(sum(p.get("Score",0) for p in postes)/n) if n else 0
total_nc = sum(p.get("NonConformes",0) for p in postes)

def badge_score(s):
    cls = "ok" if s >= 80 else ("mid" if s >= 50 else "ko")
    return f'<span class="b {cls}">{s}%</span>'

poste_rows = "\n".join(
    f"<tr><td>{html.escape(str(p.get('Poste','?')))}</td>"
    f"<td>{html.escape(str(p.get('Systeme','?')))}</td>"
    f"<td class='w'>{html.escape(str(p.get('OSDetail','')))}</td>"
    f"<td>{badge_score(p.get('Score',0))}</td>"
    f"<td>{p.get('NonConformes',0)}</td>"
    f"<td>{p.get('DureeSecondes',0)} s</td></tr>"
    for p in sorted(postes, key=lambda x: x.get('Score',0))
)

# synthese des ecarts les plus frequents
ctrl_rows = "\n".join(
    f"<tr><td class='m'>{html.escape(k)}</td><td>{html.escape(v['titre'])}</td>"
    f"<td>{html.escape(v['risque'])}</td>"
    f"<td>{v['nc']} / {v['appl']}</td></tr>"
    for k, v in sorted(by_control.items(), key=lambda kv: (-kv[1]['nc'], kv[0]))
    if v['nc'] > 0
) or "<tr><td colspan='4' class='w'>Aucun ecart detecte sur le parc audite.</td></tr>"

today = datetime.date.today().strftime("%d/%m/%Y")
out_dir = os.path.join(base, "rapports-client"); os.makedirs(out_dir, exist_ok=True)
out = os.path.join(out_dir, f"Audit-{client.replace(' ','_')}-{datetime.date.today():%Y%m%d}.html")

doc = f"""<!doctype html><html lang="fr"><head><meta charset="utf-8">
<title>Rapport d'audit - {html.escape(client)}</title><style>
body{{font:14px/1.55 -apple-system,Segoe UI,Roboto,sans-serif;color:#1a2230;margin:28px;max-width:1000px}}
h1{{font-size:22px;margin:0 0 2px}}h2{{font-size:16px;margin:26px 0 8px;border-bottom:2px solid #1f3b57;padding-bottom:4px;color:#1f3b57}}
.s{{color:#5b6677;margin:0 0 6px}}
.k{{display:flex;gap:12px;flex-wrap:wrap;margin:16px 0}}
.c{{border:1px solid #e6e9ef;border-radius:12px;padding:14px 18px;min-width:120px}}.c .n{{font-size:26px;font-weight:700}}.c .l{{color:#5b6677;font-size:12.5px}}
table{{width:100%;border-collapse:collapse;border:1px solid #e6e9ef;border-radius:12px;overflow:hidden;margin-top:6px}}
th,td{{text-align:left;padding:9px 12px;border-bottom:1px solid #e6e9ef;vertical-align:top}}
th{{font-size:11.5px;text-transform:uppercase;color:#5b6677}}
.m{{font-family:ui-monospace,Consolas,monospace;font-size:12.5px;color:#5b6677}}.w{{color:#5b6677;font-size:12.5px}}
.b{{padding:2px 9px;border-radius:999px;font-size:12px;font-weight:600}}
.b.ok{{background:#d9f0e4;color:#1a7f52}}.b.mid{{background:#fcefd6;color:#b7791f}}.b.ko{{background:#f6dcde;color:#c23b45}}
.ft{{color:#5b6677;font-size:12px;margin-top:22px;border-top:1px solid #e6e9ef;padding-top:12px}}
</style></head><body>
<h1>Rapport d'audit de securite &mdash; {html.escape(client)}</h1>
<p class="s">Audit avant correction &middot; {today} &middot; Bahiri Consultant IT MSP Cybersecurite</p>
<div class="k">
 <div class="c"><div class="n">{n}</div><div class="l">Postes audites</div></div>
 <div class="c"><div class="n">{n_win}</div><div class="l">PC Windows</div></div>
 <div class="c"><div class="n">{n_mac}</div><div class="l">Mac</div></div>
 <div class="c"><div class="n">{avg_score}%</div><div class="l">Conformite moyenne</div></div>
 <div class="c"><div class="n">{total_nc}</div><div class="l">Ecarts au total</div></div>
 <div class="c"><div class="n">{avg_dur} s</div><div class="l">Duree moyenne / poste</div></div>
</div>
<h2>Detail par poste</h2>
<table><thead><tr><th>Poste</th><th>Systeme</th><th>OS</th><th>Conformite</th><th>Ecarts</th><th>Duree</th></tr></thead>
<tbody>{poste_rows}</tbody></table>
<h2>Ecarts les plus frequents sur le parc</h2>
<table><thead><tr><th>ID</th><th>Controle</th><th>Risque</th><th>Postes concernes</th></tr></thead>
<tbody>{ctrl_rows}</tbody></table>
<p class="ft">Audit realise en lecture seule, sans aucune modification des postes. Les corrections proposees
sont validees en environnement de test avant toute application, selon le principe : la machine execute, l'humain decide.</p>
</body></html>"""

open(out, "w", encoding="utf-8").write(doc)
print(f"{n} poste(s) consolides : {n_win} PC / {n_mac} Mac, duree moyenne {avg_dur}s, conformite moyenne {avg_score}%.")
print(f"Rapport client : {out}")
try: webbrowser.open("file://" + out)
except Exception: pass

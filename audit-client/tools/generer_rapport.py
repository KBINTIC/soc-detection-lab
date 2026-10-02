#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
generer_rapport.py - Rapport d'audit consolide (AVANT correction) a partir des
rapports JSON collectes sur les postes du client.

Usage:
    python3 generer_rapport.py <dossier_mission>
    (le dossier contient un sous-dossier 'rapports' avec les .json des postes)

Produit, dans le dossier mission :
    Rapport-Audit-<client>-<date>.html   et   .pdf  (PDF via Google Chrome si present)
"""
import sys, os, json, glob, subprocess, datetime, html

NAVY="#1F3B57"; OK="#1a7f52"; KO="#c23b45"; NA="#8893a4"; GREY="#444"

def esc(s): return html.escape(str(s if s is not None else ""))
def mmss(sec):
    sec=int(round(sec)); return f"{sec//60} min {sec%60:02d}s" if sec>=60 else f"{sec}s"

def main():
    if len(sys.argv)<2:
        print("Usage: python3 generer_rapport.py <dossier_mission>"); sys.exit(1)
    mission=os.path.abspath(sys.argv[1])
    files=sorted(glob.glob(os.path.join(mission,"rapports","*.json")))
    if not files:
        print("Aucun rapport JSON dans", os.path.join(mission,"rapports")); sys.exit(1)
    postes=[]
    for f in files:
        try: postes.append(json.load(open(f,encoding="utf-8")))
        except Exception as e: print("Ignore",f,":",e)
    if not postes: print("Aucun rapport lisible."); sys.exit(1)

    client = next((p.get("client") for p in postes if p.get("client")), "") or "Client"
    nb=len(postes); nb_pc=sum(1 for p in postes if p.get("type")=="PC"); nb_mac=sum(1 for p in postes if p.get("type")=="Mac")
    duree_moy=sum(p.get("duree_secondes",0) for p in postes)/nb
    score_moy=round(sum(p.get("score",0) for p in postes)/nb)
    ecarts=sum(p.get("non_conformes",0) for p in postes)
    gen=datetime.datetime.now().strftime("%d/%m/%Y %H:%M")

    # Synthese par poste
    rows_postes=""
    for p in sorted(postes,key=lambda x:x.get("poste","")):
        rows_postes+=f"""<tr><td class='mono'>{esc(p.get('poste'))}</td><td>{esc(p.get('type'))}</td>
        <td>{esc(p.get('os'))}</td><td>{mmss(p.get('duree_secondes',0))}</td>
        <td><b>{esc(p.get('score'))}%</b></td><td style='color:{KO}'>{esc(p.get('non_conformes'))}</td></tr>"""

    # Detail des ecarts par poste
    detail=""
    for p in sorted(postes,key=lambda x:x.get("poste","")):
        ncs=[c for c in p.get("controles",[]) if c.get("statut")=="NonConforme"]
        if not ncs: continue
        detail+=f"<h3>{esc(p.get('poste'))} <span class='sub'>({esc(p.get('type'))} · {esc(p.get('os'))})</span></h3>"
        detail+="<table><thead><tr><th>ID</th><th>Contrôle</th><th>Risque</th><th>Constat</th></tr></thead><tbody>"
        for c in ncs:
            detail+=f"""<tr><td class='mono'>{esc(c.get('id'))}</td>
            <td>{esc(c.get('titre'))}<div class='why'>{esc(c.get('pourquoi'))}</div></td>
            <td>{esc(c.get('risque'))}</td><td>{esc(c.get('actuel'))}</td></tr>"""
        detail+="</tbody></table>"

    # Corrections a valider en lab (uniques par id)
    seen={}
    for p in postes:
        for c in p.get("controles",[]):
            if c.get("statut")=="NonConforme" and c.get("id") not in seen:
                seen[c["id"]]=c
    reco=""
    if seen:
        reco="<table><thead><tr><th>ID</th><th>Correction proposée</th></tr></thead><tbody>"
        for cid,c in sorted(seen.items()):
            reco+=f"<tr><td class='mono'>{esc(cid)}</td><td><b>{esc(c.get('titre'))}</b><div class='cmd'>{esc(c.get('correction'))}</div></td></tr>"
        reco+="</tbody></table>"

    doc=f"""<!doctype html><html lang="fr"><head><meta charset="utf-8">
<style>
@page {{ size:A4; margin:14mm 12mm; }}
*{{box-sizing:border-box}} body{{margin:0;color:#1a2230;font:13px/1.5 -apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif}}
.hd{{background:{NAVY};color:#fff;padding:16px 18px;border-radius:8px;display:flex;justify-content:space-between;align-items:flex-start}}
.hd h1{{margin:0 0 4px;font-size:20px}} .hd .s{{color:#cfd9e6;font-size:12px}}
.hd .r{{text-align:right;font-size:12px;color:#e7edf4}}
h2{{font-size:15px;color:{NAVY};border-bottom:2px solid {NAVY};padding-bottom:4px;margin:22px 0 8px;text-transform:uppercase;letter-spacing:.03em}}
h3{{font-size:14px;margin:16px 0 4px}} .sub{{color:{GREY};font-weight:normal;font-size:12px}}
.kpis{{display:flex;gap:10px;margin:14px 0}}
.kpi{{flex:1;border:1px solid #e6e9ef;border-radius:10px;padding:12px 14px}}
.kpi .n{{font-size:24px;font-weight:700;color:{NAVY}}} .kpi .l{{font-size:11px;color:{GREY}}}
table{{width:100%;border-collapse:collapse;margin-top:6px}}
th,td{{text-align:left;padding:7px 9px;border-bottom:1px solid #e6e9ef;vertical-align:top;font-size:12px}}
th{{font-size:10.5px;text-transform:uppercase;letter-spacing:.03em;color:{GREY}}}
.mono{{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:11.5px;color:{GREY}}}
.why{{color:{GREY};font-size:11px;margin-top:2px}}
.cmd{{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:11px;background:#0f1722;color:#d7e2f4;padding:4px 7px;border-radius:5px;margin-top:4px;white-space:pre-wrap;word-break:break-word}}
.note{{background:#fff7e6;border:1px solid #f0d9a8;border-radius:8px;padding:9px 12px;font-size:12px;margin-top:8px}}
.ft{{color:{GREY};font-size:10.5px;margin-top:20px;border-top:1px solid #e6e9ef;padding-top:8px}}
</style></head><body>
<div class="hd"><div><h1>Rapport d'audit de sécurité — avant correction</h1>
<div class="s">Client : {esc(client)}</div></div>
<div class="r">Bahiri Consultant IT<br>MSP &amp; Cybersécurité<br>contact@kbahiri.com<br>{gen}</div></div>

<h2>Synthèse</h2>
<div class="kpis">
<div class="kpi"><div class="n">{nb}</div><div class="l">Postes audités<br>({nb_pc} PC · {nb_mac} Mac)</div></div>
<div class="kpi"><div class="n">{score_moy}%</div><div class="l">Conformité moyenne</div></div>
<div class="kpi"><div class="n">{ecarts}</div><div class="l">Écarts détectés</div></div>
<div class="kpi"><div class="n">{mmss(duree_moy)}</div><div class="l">Durée moyenne / poste</div></div>
</div>
<table><thead><tr><th>Poste</th><th>Type</th><th>Système</th><th>Durée</th><th>Score</th><th>Écarts</th></tr></thead>
<tbody>{rows_postes}</tbody></table>
<div class="note"><b>Audit en lecture seule :</b> aucune modification n'a été appliquée sur les postes.
Les corrections ci-dessous sont d'abord validées en environnement de test (VM lab) avant toute application,
avec rapport avant/après et possibilité de retour arrière.</div>

<h2>Détail des écarts par poste</h2>
{detail or "<p>Aucun écart détecté.</p>"}

<h2>Corrections proposées (à valider en lab)</h2>
{reco or "<p>Aucune correction nécessaire.</p>"}

<div class="ft">Bahiri Consultant IT — MSP &amp; Cybersécurité · contact@kbahiri.com · SIRET 381 532 902 00040.
Rapport généré automatiquement le {gen}. Audit non intrusif, conforme au principe « la machine exécute, l'humain décide ».</div>
</body></html>"""

    safe_client="".join(ch for ch in client if ch.isalnum() or ch in "-_ ").strip().replace(" ","_") or "Client"
    stamp=datetime.datetime.now().strftime("%Y%m%d")
    base=os.path.join(mission,f"Rapport-Audit-{safe_client}-{stamp}")
    html_path=base+".html"; pdf_path=base+".pdf"
    open(html_path,"w",encoding="utf-8").write(doc)
    print("HTML :",html_path)

    # PDF via Google Chrome headless
    chromes=["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
             "/Applications/Chromium.app/Contents/MacOS/Chromium",
             "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"]
    chrome=next((c for c in chromes if os.path.exists(c)),None)
    if chrome:
        for flags in (["--headless=new"],["--headless"]):
            try:
                subprocess.run([chrome,*flags,"--disable-gpu","--no-pdf-header-footer",
                    f"--print-to-pdf={pdf_path}","--virtual-time-budget=4000",
                    "file://"+html_path],check=True,timeout=60,
                    stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
                if os.path.exists(pdf_path) and os.path.getsize(pdf_path)>1000:
                    print("PDF  :",pdf_path); break
            except Exception: continue
        else:
            print("PDF non généré automatiquement. Ouvrez le HTML et faites Cmd+P > Enregistrer en PDF.")
    else:
        print("Google Chrome introuvable. Ouvrez le HTML et faites Cmd+P > Enregistrer en PDF.")

if __name__=="__main__":
    main()

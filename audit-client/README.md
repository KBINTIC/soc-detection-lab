# Audit client — mission d'audit de sécurité sur site

Processus d'audit **non intrusif (lecture seule)** des postes d'un client (Windows et macOS),
piloté depuis le Mac consultant, avec rapport PDF à l'en-tête Bahiri Consultant IT.

> Principe : **la machine exécute, l'humain décide.** L'audit ne modifie rien ; les corrections
> sont validées sur la VM de lab *avant* toute application chez le client.

## Déroulé (vue d'ensemble)

1. **Au bureau** — `Demarrer-Audit-Client.command` : saisir le client, préparer la clé USB.
2. **Sur site** — auditer chaque poste (≈ 30–60 s / poste) :
   - Windows : `Lancer-Audit-Windows.bat` (clé USB, admin).
   - Mac : `audit-poste-mac.command` (sudo).
   - ou **audit distant** SSH (même réseau).
3. **Rapport** — rapatrier les rapports JSON, générer le **PDF** (postes PC/Mac, conformité moyenne, écarts, **durée moyenne**).
4. **Lab** — valider chaque correction sur la VM : voir **`CAHIER-VALIDATION-VM.md`** (commande + annulation), puis `hardening-toolkit` (mode `-WhatIf` puis réel), réversible.
5. **Client** — appliquer les corrections validées, puis rapport après.

Le mode opératoire détaillé et illustré est dans **`RUNBOOK.html`** (ouvert par le menu, choix 6).

## Contenu

```
audit-client/
├─ Demarrer-Audit-Client.command   ← orchestrateur (Mac consultant)
├─ RUNBOOK.html                    ← mode opératoire pas à pas
├─ CAHIER-VALIDATION-VM.md         ← chaque correction + commande d'annulation, à tester sur la VM
├─ kit/                            ← kit portable (clé USB)
│  ├─ Audit-Poste-Windows.ps1      ← audit Windows (lecture seule, JSON)
│  ├─ Lancer-Audit-Windows.bat     ← double-clic côté client Windows
│  └─ audit-poste-mac.command      ← audit macOS (lecture seule, JSON)
├─ tools/
│  ├─ generer_rapport.py           ← rapport d'audit consolidé (HTML + PDF)
│  └─ audit-distant.sh             ← audit d'un Mac distant via SSH
└─ missions/                       ← un dossier par mission (date + client)
```

## Rapport d'audit — indicateurs

Le PDF consolidé (généré sur le Mac via Google Chrome) contient :

- **Nombre de postes audités**, dont **PC** et **Mac**.
- **Durée moyenne par poste** (mesurée par chaque audit).
- **Conformité moyenne** et **nombre d'écarts**.
- Synthèse par poste, détail des écarts, et **corrections proposées (à valider en lab)**.

## Contrôles

- **Windows** : pare-feu, antivirus/EDR, SMBv1, LLMNR, NTLMv2, RDP/NLA, compte invité, BitLocker,
  journalisation PowerShell, audit des comptes, mises à jour récentes.
- **macOS** : pare-feu applicatif + mode furtif, FileVault, Gatekeeper, SIP, mises à jour auto,
  SSH/connexion à distance, compte invité, verrouillage de session.

Les identifiants (FW-001, LLMNR-001…) sont alignés sur la suite `hardening-toolkit`,
pour valider puis appliquer les corrections de façon traçable.

## Prérequis (Mac consultant)

- `python3` (fourni avec les outils de développement ; présent via Anaconda).
- **Google Chrome** pour le PDF (sinon : ouvrir le HTML et Cmd+P → Enregistrer en PDF).
- Pour l'audit distant : SSH activé sur le poste Mac client (Réglages > Partage > Connexion à distance).

## Précautions

- Audit **lecture seule** : aucune modification pendant la mission.
- Les postes des clients ne sont **jamais** modifiés sans validation préalable en lab et accord du client.
- Les rapports contiennent des informations sur le parc du client : les conserver de façon sécurisée.

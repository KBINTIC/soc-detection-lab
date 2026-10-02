# Kit d'audit terrain — procédure documentée

Audit de sécurité des postes d'un client (Windows et Mac), **en lecture seule**, depuis une clé USB.
Principe : la machine exécute, l'humain décide. **Aucune correction n'est faite pendant l'audit.**

```
 Préparation (ton Mac)      Chez le client (par poste)        Retour (ton Mac)
 ┌───────────────────┐      ┌────────────────────────┐        ┌───────────────────────┐
 │ copier audit-kit  │  →   │ brancher la clé USB    │   →    │ Consolider-Audit      │
 │ sur la clé USB    │      │ lancer l'audit (lecture│        │ → rapport client      │
 └───────────────────┘      │ seule) → rapport poste │        │ (nb PC/Mac, durée moy.)│
                            └────────────────────────┘        └───────────────────────┘
```

## Contenu de la clé

```
audit-kit/
├─ Windows/Demarrer-Audit.cmd      ← sur un PC client : clic droit > Exécuter en administrateur
├─ Windows/audit-windows.ps1
├─ Mac/Demarrer-Audit.command      ← sur un Mac client : double-clic
├─ Mac/audit-mac.sh
├─ postes/                         ← un dossier par poste audité (JSON + rapport HTML)
├─ rapports-client/                ← rapports consolidés (créé à la consolidation)
└─ sur-mon-mac/
   ├─ Consolider-Audit.command     ← sur TON Mac : agrège tous les postes
   ├─ consolider.py
   └─ Cahier-validation-VM.md      ← les corrections à valider sur ta VM AVANT application
```

## 1. Préparer la clé (depuis ton Mac, une fois)

1. Formate une clé USB en **exFAT** (lisible Windows et Mac).
2. Copie le dossier `audit-kit` à la racine de la clé.
3. Vide le dossier `postes/` si des audits précédents s'y trouvent (ou garde-les pour historique).

## 2. Chez le client — pour CHAQUE poste (durée indicative : 1 à 2 min/poste)

**Sur un PC Windows :**
1. Branche la clé.
2. Ouvre le dossier `audit-kit\Windows`.
3. **Clic droit sur `Demarrer-Audit.cmd` > « Exécuter en tant qu'administrateur ».**
4. L'audit se déroule à l'écran (lignes `[OK]` / `[!!]` / `[--]`), se chronomètre, puis ouvre le rapport du poste. Montre-le au client : c'est concret et pédagogique.

**Sur un Mac :**
1. Branche la clé.
2. Ouvre `audit-kit/Mac` et **double-clique sur `Demarrer-Audit.command`**.
   - Si macOS bloque : clic droit > **Ouvrir**, puis **Ouvrir**.
3. Saisis le **mot de passe administrateur du Mac** (demandé pour lire certains réglages). L'audit ne modifie rien.
4. Le rapport du poste s'ouvre à la fin.

Chaque poste écrit son rapport dans `postes/<nom-du-poste>-WIN|MAC-<date>/` : un `audit.json` et un `rapport-poste.html`. La **durée de l'audit** figure dans chaque rapport.

> Astuce : audite tous les postes du client les uns après les autres. Ils s'accumulent dans `postes/`.

## 3. De retour — consolider (sur ton Mac)

1. Branche la clé sur ton Mac (ou travaille directement dessus).
2. Dans `audit-kit/sur-mon-mac`, double-clique sur **`Consolider-Audit.command`**.
3. Saisis le **nom du client**.
4. Le **rapport client** s'ouvre : nombre de postes audités (PC / Mac), **durée moyenne d'audit**, conformité moyenne, détail par poste, et les écarts les plus fréquents sur le parc. Il est dans `rapports-client/`.
5. Pour le livrer en PDF : dans le navigateur, **Fichier > Imprimer > Enregistrer au format PDF**.

## 4. Proposer les corrections (après l'audit)

L'audit montre les écarts ; la **correction est une étape distincte**, jamais faite dans la précipitation.

1. Sur **ta VM de lab**, valide chaque commande de correction concernée — voir **`sur-mon-mac/Cahier-validation-VM.md`**.
2. Une fois validées, applique-les chez le client avec la suite `hardening-toolkit` (audit « avant », durcissement avec validation O/N, audit « après », rapport avant/après). Chaque correction y est réversible.

## Ce que l'audit vérifie

**Windows** : pare-feu (3 profils), protection temps réel (Defender / N/A si EDR tiers), SMBv1, LLMNR, NTLMv2,
RDP/NLA, compte invité, BitLocker, fraîcheur des mises à jour, journalisation PowerShell.

**Mac** : pare-feu applicatif, mode furtif, FileVault, Gatekeeper, SIP, mises à jour automatiques,
connexion à distance (SSH), partage d'écran, partage de fichiers, compte invité.

## Rappels

- L'audit est **100 % lecture seule**. Tu peux le lancer devant le client en toute confiance.
- Demande l'**accord écrit** du client avant toute intervention (audit comme correction).
- Les rapports contiennent des informations sur le parc : traite la clé et les rapports comme des données confidentielles.

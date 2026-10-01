# SOC Detection Lab

Detection-as-code for small-business environments (Windows endpoints + Microsoft 365).
Detection rules are written once in **[Sigma](https://sigmahq.io)**, validated in CI, and converted automatically to:

- **Microsoft Sentinel** (KQL), through a custom pySigma pipeline ([`pipelines/sentinel.yml`](pipelines/sentinel.yml))
- **Wazuh** (OpenSearch Lucene), through a custom pySigma pipeline ([`pipelines/wazuh.yml`](pipelines/wazuh.yml))

Every rule is tested against real events generated in a home lab (Wazuh in Docker + Windows VM + M365 test tenant).

> **FR**: Laboratoire de détection orienté TPE/PME. Les règles sont écrites en Sigma, validées automatiquement
> et converties pour Microsoft Sentinel et Wazuh. Chaque règle est testée sur des événements réels.

## Why

On the client side I deploy and operate EDR/XDR (Bitdefender GravityZone) and audit Microsoft 365 and workstation
hardening. This repository is the SOC side of that work: turning what attackers actually do in small businesses
(mailbox takeover, MFA removal, security tooling disabled, hardening rolled back) into portable, testable detections.

## Repository layout

```
rules/            Sigma rules (windows/, m365/)
pipelines/        pySigma processing pipelines: field mappings and log sources for Sentinel and Wazuh
scripts/          convert.sh: one query file per rule and backend, written to build/
lab/              Home lab: Wazuh on Docker (macOS), Windows agent, Sysmon and M365 collection configs
docs/             Detection catalogue, ATT&CK mapping, simulation commands
.github/workflows CI: validate every rule, convert to both backends, publish the queries as an artifact
```

## Detections

See the full catalogue with simulation steps in [docs/detections.md](docs/detections.md).

| Area | Detection | ATT&CK |
|---|---|---|
| Windows | Defender real-time protection disabled | T1562.001 |
| Windows | Security event log cleared | T1070.001 |
| Windows | PowerShell with encoded command | T1059.001 |
| Windows | Member added to local Administrators | T1098 |
| Windows | LLMNR re-enabled via registry | T1557.001 |
| M365 | Inbox rule forwarding or redirecting mail | T1114.003 |
| M365 | MFA disabled for a user | T1556.006 |
| M365 | FullAccess granted on a mailbox | T1098.002 |

## Quick start

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

sigma check rules/          # validate
./scripts/convert.sh        # build/sentinel/*.kql and build/wazuh/*.lucene
```

Example output for the forwarding-rule detection:

```kql
OfficeActivity
| where (Operation in~ ("New-InboxRule", "Set-InboxRule")) and (Parameters contains "ForwardTo" or Parameters contains "ForwardAsAttachmentTo" or Parameters contains "RedirectTo")
```

```
rule.groups:office365 AND ((data.office365.Operation:(New\-InboxRule OR Set\-InboxRule)) AND ((data.office365.Parameters.Name:(*ForwardTo* OR ...
```

To run the lab itself, see [lab/README.md](lab/README.md).

## Design notes and known limitations

- **Sentinel**: Windows process and registry rules target the **ASIM** parsers (`imProcessCreate`, `imRegistry`), so
  they work whatever the source (Sysmon, MDE, 4688). Sigma's `TargetObject` (key + value name) is rebuilt from
  ASIM's `RegistryKey` + `RegistryValue`, and Sysmon's `DWORD (0x00000001)` notation is translated to ASIM's `1`.
- **Wazuh**: queries target `wazuh-archives-*` (all events), because most Sysmon events do not raise a built-in
  Wazuh alert and would otherwise be missing from `wazuh-alerts-*`.
- **Case sensitivity**: Sigma matching is case-insensitive, but Lucene wildcard queries on Wazuh keyword fields are
  case-sensitive. Values are written as Windows logs them (e.g. `\SOFTWARE\Policies\...`), but a command line like
  `-ENC` would be missed on Wazuh (not on Sentinel). The next step is to ship the same logic as native Wazuh XML
  rules (PCRE2 with case-insensitive matching).
- **M365 `Parameters`**: Sentinel stores it as a JSON string; Wazuh as a list of `{Name, Value}` objects. The Wazuh
  pipeline searches both sub-fields.

## Roadmap

- [ ] Native Wazuh XML rules generated from Sigma (case-insensitive, real-time alerts)
- [ ] Sigma correlation rules (password spraying, impossible travel)
- [ ] Automated triage: enrich alerts (VirusTotal, AbuseIPDB) through Wazuh integrations / SOAR (Shuffle)
- [ ] Event-based unit tests: replay recorded events and assert which rules fire

## License

MIT, see [LICENSE](LICENSE).

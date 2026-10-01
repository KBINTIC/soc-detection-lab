# Lab setup (macOS)

Target: a Wazuh SIEM in Docker on a Mac, one Windows VM sending Security, Sysmon and Defender logs,
and optionally a Microsoft 365 **test** tenant.

```
 Windows VM (UTM / VMware Fusion)            Mac (Docker Desktop)
 ┌──────────────────────────────┐           ┌───────────────────────────────┐
 │ Sysmon + Defender + Security │──agent───▶│ wazuh.manager  (1514/1515)    │
 └──────────────────────────────┘           │ wazuh.indexer  (OpenSearch)   │
 Microsoft 365 test tenant ──Mgmt API──────▶│ wazuh.dashboard https://localhost
                                            └───────────────────────────────┘
```

## 1. Requirements

- Mac with 16 GB RAM or more (Wazuh alone needs about 8 GB, the Windows VM 4 GB).
- Docker Desktop, with **Resources > Memory set to at least 8 GB** and 4 CPUs.
- About 60 GB of free disk space.
- A Windows VM:
  - Apple Silicon: Windows 11 ARM in UTM (free) or VMware Fusion (free for personal use).
    Use `Sysmon64a.exe` (ARM build). The Wazuh agent is an x86/x64 installer that runs under Windows' built-in emulation. Check enrolment works before going further.
  - Intel Mac: any Windows 10/11 x64 VM.

## 2. Start Wazuh

```bash
./lab/setup.sh
```

The script pins `wazuh-docker` **v4.14.8**, enables full event archiving (`logall_json` plus Filebeat archives) so that
*every* event is searchable, not only the ones that trigger a built-in Wazuh rule, then starts the stack.

Then open https://localhost (self-signed certificate), log in as `admin` / `SecretPassword`, and create the
index pattern **`wazuh-archives-*`** (Dashboard Management > Index patterns, time field `timestamp`).

Stop and restart the lab:

```bash
cd lab/wazuh-docker/single-node && docker compose stop     # keep data
docker compose start
docker compose down -v                                      # wipe everything
```

## 3. Windows VM

**Shortcut**: run `lab/agent/install-lab-agent.ps1` in an elevated PowerShell inside the VM. It installs Sysmon, the Wazuh agent, the extra channels and the audit policies (steps 1 to 3 below).

1. **Sysmon**: download it from Microsoft Sysinternals, copy `lab/agent/sysmon-lab.xml` to the VM, then:
   `Sysmon64.exe -accepteula -i sysmon-lab.xml`
2. **Wazuh agent**: in the dashboard, go to *Agents management > Deploy new agent > Windows*. Use your Mac's IP
   *as seen from the VM* as the server address (with UTM shared networking this is usually `192.168.64.1`; check with `ipconfig` on the VM gateway).
   Run the generated PowerShell command in the VM, then `NET START WazuhSvc`.
3. **Extra channels**: add the content of `lab/agent/ossec-localfile.xml` to
   `C:\Program Files (x86)\ossec-agent\ossec.conf`, then `Restart-Service WazuhSvc`.
4. Check: in Discover (`wazuh-archives-*`), filter on `data.win.system.channel` and confirm you see Security,
   Sysmon and Defender events.

## 4. Microsoft 365 (optional, test tenant only)

1. In Entra ID, go to *App registrations > New registration* (single tenant).
2. *API permissions > Add > Office 365 Management APIs > Application permissions > `ActivityFeed.Read`*, then **Grant admin consent**.
3. *Certificates & secrets > New client secret*, and copy the value.
4. Make sure unified audit logging is on (Purview > Audit).
5. `cp lab/manager/office365.example.xml lab/manager/office365.local.xml`, fill in the tenant ID, client ID and secret,
   then append the block to the manager config and restart:
   ```bash
   cat lab/manager/office365.local.xml >> lab/wazuh-docker/single-node/config/wazuh_cluster/wazuh_manager.conf
   cd lab/wazuh-docker/single-node && docker compose restart wazuh.manager
   ```
   (If you have not run `setup.sh` yet, it does this for you.)
6. Check: in Discover, query `rule.groups:office365`. The first records can take 30 to 60 minutes to arrive.

Never point the lab at a client tenant: this is a test environment with default passwords.

## 5. Test the detections

Follow [docs/detections.md](../docs/detections.md): run the simulation commands, then paste the matching
query from `build/wazuh/` into Discover and confirm the event is found. Record the result (screenshot, date)
in the rule's pull request. That evidence is what makes the repository credible.

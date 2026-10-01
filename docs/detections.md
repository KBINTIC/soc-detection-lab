# Detections catalogue

Each rule is written once in Sigma and converted to Microsoft Sentinel (KQL) and Wazuh (OpenSearch Lucene) by CI.
The **Simulate** column gives a safe command to trigger the rule in the lab. Run it only on a lab VM or test tenant.

| Rule | ATT&CK | Level | Log source |
|---|---|---|---|
| [Defender real-time protection disabled](../rules/windows/win_defender_realtime_protection_disabled.yml) | T1562.001 | high | Defender Operational, event 5001 |
| [Security event log cleared](../rules/windows/win_security_log_cleared.yml) | T1070.001 | high | Security, event 1102 |
| [PowerShell with encoded command](../rules/windows/win_powershell_encoded_command.yml) | T1059.001, T1027 | medium | Sysmon 1 / process creation |
| [Member added to local Administrators](../rules/windows/win_local_admin_group_member_added.yml) | T1098 | medium | Security, event 4732 |
| [LLMNR re-enabled via registry](../rules/windows/win_llmnr_reenabled_registry.yml) | T1557.001, T1112 | medium | Sysmon 13 / registry set |
| [M365 inbox rule forwarding mail](../rules/m365/m365_inbox_rule_forwarding.yml) | T1114.003 | high | M365 unified audit log |
| [M365 MFA disabled for a user](../rules/m365/m365_mfa_disabled_for_user.yml) | T1556.006 | high | M365 unified audit log |
| [M365 FullAccess granted on a mailbox](../rules/m365/m365_mailbox_fullaccess_granted.yml) | T1098.002 | medium | M365 unified audit log |

## Simulate (Windows VM, elevated PowerShell)

```powershell
# 1. Defender real-time protection off (turn Tamper Protection off first in Windows Security), then back on
Set-MpPreference -DisableRealtimeMonitoring $true
Set-MpPreference -DisableRealtimeMonitoring $false

# 2. Clear the Security log
wevtutil cl Security

# 3. Encoded PowerShell (payload = Write-Host "sigma lab test")
powershell.exe -enc VwByAGkAdABlAC0ASABvAHMAdAAgACIAcwBpAGcAbQBhACAAbABhAGIAIAB0AGUAcwB0ACIA

# 4. Local admin group change (make sure group management auditing is on)
auditpol /set /subcategory:"{0CCE9237-69AE-11D9-BED3-505054503030}" /success:enable   # Security Group Management (works on any Windows language)
net user labuser 'L@b-Only-2026!' /add
net localgroup Administrators labuser /add
net localgroup Administrators labuser /delete
net user labuser /delete

# 5. LLMNR re-enabled, then hardened again
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" /v EnableMulticast /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" /v EnableMulticast /t REG_DWORD /d 0 /f
```

## Simulate (Microsoft 365 test tenant)

Audit records can take 30 minutes or more to show up in the Management Activity API.

```powershell
Connect-ExchangeOnline -UserPrincipalName admin@yourtesttenant.onmicrosoft.com

# 6. Forwarding inbox rule (then remove it)
New-InboxRule -Mailbox testuser -Name "lab-forward" -ForwardTo "someone@example.com"
Remove-InboxRule -Mailbox testuser -Identity "lab-forward" -Confirm:$false

# 8. FullAccess delegation (then remove it)
Add-MailboxPermission -Identity testuser -User testadmin -AccessRights FullAccess
Remove-MailboxPermission -Identity testuser -User testadmin -AccessRights FullAccess -Confirm:$false
```

7. MFA disabled: in the Entra admin center, open the legacy per-user MFA page, enable MFA for a test user, then disable it.

## Hunting with the converted queries

- **Wazuh**: Dashboard > Discover, index pattern `wazuh-archives-*`, paste the content of `build/wazuh/<rule>.lucene` (query language: Lucene).
  To get an alert, save it as a monitor in the Alerting plugin.
- **Sentinel**: Logs, paste `build/sentinel/<rule>.kql`, or create an Analytics rule (scheduled query) from it.

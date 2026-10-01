# SOC Detection Lab - Windows VM setup (run in an ELEVATED PowerShell)
# Installs Sysmon (lab config), the Wazuh agent, extra event channels and audit policies.
# Lab use only. Usage:  Set-ExecutionPolicy -Scope Process Bypass -Force; .\install-lab-agent.ps1
param(
  [string]$Manager   = '192.168.64.1',      # the Mac, as seen from a UTM "shared network" VM
  [string]$AgentName = 'WIN-LAB',
  [string]$WazuhMsi  = 'https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.8-1.msi'
)
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
$work = Join-Path $env:TEMP 'soclab'; New-Item -ItemType Directory -Force $work | Out-Null
function Step($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }

Step "0. Reaching the Wazuh manager ($Manager)"
foreach ($p in 1514,1515) {
  $ok = (Test-NetConnection $Manager -Port $p -WarningAction SilentlyContinue).TcpTestSucceeded
  Write-Host "  port $p : $ok"
  if (-not $ok) { throw "Cannot reach $Manager`:$p. Is Docker/Wazuh running on the Mac? Check the VM network (UTM shared network)." }
}

Step "1. Sysmon"
$sysmonCfg = Join-Path $work 'sysmon-lab.xml'
@'
<Sysmon schemaversion="4.90">
  <HashAlgorithms>sha256</HashAlgorithms>
  <EventFiltering>
    <RuleGroup name="process" groupRelation="or">
      <ProcessCreate onmatch="exclude" />
    </RuleGroup>
    <RuleGroup name="registry" groupRelation="or">
      <RegistryEvent onmatch="include">
        <TargetObject condition="contains">\SOFTWARE\Policies\</TargetObject>
        <TargetObject condition="contains">\CurrentVersion\Run</TargetObject>
        <TargetObject condition="contains">\Control\Lsa\</TargetObject>
        <TargetObject condition="contains">\Services\NetBT\Parameters</TargetObject>
      </RegistryEvent>
    </RuleGroup>
  </EventFiltering>
</Sysmon>
'@ | Set-Content -Encoding ASCII $sysmonCfg
Invoke-WebRequest 'https://download.sysinternals.com/files/Sysmon.zip' -OutFile "$work\Sysmon.zip"
Expand-Archive "$work\Sysmon.zip" -DestinationPath "$work\Sysmon" -Force
$exe = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'Sysmon64a.exe' } else { 'Sysmon64.exe' }
$sysmon = Join-Path "$work\Sysmon" $exe
if (Get-Service -Name 'Sysmon64*' -ErrorAction SilentlyContinue) { & $sysmon -c $sysmonCfg }
else { & $sysmon -accepteula -i $sysmonCfg }

Step "2. Wazuh agent"
Invoke-WebRequest $WazuhMsi -OutFile "$work\wazuh-agent.msi"
Start-Process msiexec.exe -Wait -ArgumentList "/i `"$work\wazuh-agent.msi`" /q WAZUH_MANAGER=`"$Manager`" WAZUH_AGENT_NAME=`"$AgentName`""
$conf = "${env:ProgramFiles(x86)}\ossec-agent\ossec.conf"
if (-not (Select-String -Path $conf -Pattern 'Sysmon/Operational' -Quiet)) {
  Add-Content -Path $conf -Value @'

<ossec_config>
  <localfile>
    <location>Microsoft-Windows-Sysmon/Operational</location>
    <log_format>eventchannel</log_format>
  </localfile>
  <localfile>
    <location>Microsoft-Windows-Windows Defender/Operational</location>
    <log_format>eventchannel</log_format>
  </localfile>
</ossec_config>
'@
}

Step "3. Audit policies (language-independent GUIDs)"
auditpol /set /subcategory:"{0CCE9237-69AE-11D9-BED3-505054503030}" /success:enable /failure:enable  # Security Group Management
auditpol /set /subcategory:"{0CCE9235-69AE-11D9-BED3-505054503030}" /success:enable /failure:enable  # User Account Management

Step "4. Starting the agent"
Restart-Service WazuhSvc -ErrorAction SilentlyContinue
if ((Get-Service WazuhSvc).Status -ne 'Running') { Start-Service WazuhSvc }
Start-Sleep 10
Get-Service WazuhSvc, Sysmon64* | Format-Table Name, Status -AutoSize
Get-Content "${env:ProgramFiles(x86)}\ossec-agent\ossec.log" -Tail 8

Write-Host "`nDone. In Wazuh (https://localhost) the agent '$AgentName' should appear as Active within a minute." -ForegroundColor Green

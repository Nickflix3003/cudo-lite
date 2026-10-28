---
name: fix-pc
description: Read-only Windows diagnosis runbook, then a ranked list of causes and safe repairs. Use when the owner says "fix my pc", "computer problems", "my computer is slow", "slow", "freezing", "crashing", "blue screen", "won't boot right", "restarts by itself", "diagnose", or "what's wrong with my computer".
---

# /fix-pc: diagnose first, repair only with a restore point and a yes

All commands run in PowerShell on Windows. Part 1 is read-only: run it freely. Part 3 changes the PC: every item needs the `change-ledger` steps (restore point, one-line change and undo, typed yes, ledger row).

First ask the owner: what has been going wrong, since when, and what changed recently. Use the answers to decide which checks below matter most. Run a few at a time and explain what each shows in plain English. If a command errors, note it and move on.

## Part 1: Diagnose (read-only)

1. **System summary and uptime**
   `Get-ComputerInfo -Property CsName,WindowsProductName,WindowsVersion,OsBuildNumber,CsManufacturer,CsModel,CsTotalPhysicalMemory,OsLastBootUpTime`
   `(Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime`
   A PC that has not restarted in weeks can explain slowness.
2. **Disk space**: `Get-PSDrive -PSProvider FileSystem`
   Under 10 percent free on C: is a problem by itself.
3. **Disk health**
   `Get-PhysicalDisk | Select FriendlyName,MediaType,HealthStatus,OperationalStatus`
   `Get-PhysicalDisk | Get-StorageReliabilityCounter | Select DeviceId,Temperature,Wear,ReadErrorsTotal,WriteErrorsTotal` (works only on some drives; skip if it errors)
   Anything other than Healthy is serious: tell the owner to back up important files first.
4. **Memory**
   `Get-CimInstance Win32_PhysicalMemory | Select Manufacturer,Capacity,Speed`
   `$os = Get-CimInstance Win32_OperatingSystem; "{0:N1} GB used of {1:N1} GB" -f (($os.TotalVisibleMemorySize-$os.FreePhysicalMemory)/1MB),($os.TotalVisibleMemorySize/1MB)`
5. **CPU and top processes**
   `Get-Process | Sort CPU -Descending | Select -First 15 Name,CPU,WS`
   `Get-Process | Sort WS -Descending | Select -First 10 Name,WS`
   Name each unfamiliar process in plain English before suggesting anything about it.
6. **Recent errors and critical events (14 days)**
   `Get-WinEvent -FilterHashtable @{LogName='System';Level=1,2;StartTime=(Get-Date).AddDays(-14)} | Select -First 40 TimeCreated,Id,ProviderName,Message`
   `Get-WinEvent -FilterHashtable @{LogName='Application';Level=1,2;StartTime=(Get-Date).AddDays(-14)} | Select -First 40 TimeCreated,Id,ProviderName,Message`
   Look for the same provider or id repeating.
7. **Unexpected shutdowns and crashes**
   `Get-WinEvent -FilterHashtable @{LogName='System';Id=41,1001,6008;StartTime=(Get-Date).AddDays(-30)} | Select TimeCreated,Id,ProviderName,Message`
   41 = restarted without a clean shutdown, 1001 = a crash report was made, 6008 = the previous shutdown was unexpected.
8. **Crash dumps**: `Get-ChildItem C:\Windows\Minidump -ErrorAction SilentlyContinue | Select Name,Length,LastWriteTime`
   Count and dates show how often it crashes. Do not open or send the files anywhere.
9. **Devices with errors**: `Get-PnpDevice | Where Status -ne 'OK' | Select FriendlyName,Class,Status,InstanceId`
10. **Drivers (display, network, storage)**
    `Get-CimInstance Win32_PnPSignedDriver | Where DeviceClass -in 'DISPLAY','NET','SCSIADAPTER','HDC' | Select DeviceName,DriverVersion,DriverDate`
    Note drivers older than two years or dated right before the problem began.
11. **Startup items**
    `Get-CimInstance Win32_StartupCommand | Select Name,Command,Location`
    `Get-ScheduledTask | Where { $_.State -eq 'Ready' -and ($_.Triggers | Where { $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' }) } | Select TaskName,TaskPath`
12. **Windows Update state**
    `Get-HotFix | Sort InstalledOn -Descending | Select -First 10 HotFixID,Description,InstalledOn`
    Pending reboot, first check: `Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'`
    Pending reboot, second check: `$null -ne (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue)`
    True on either means a restart is waiting; restarting first is the safest fix.
13. **Network basics**
    `Get-NetAdapter | Select Name,Status,LinkSpeed,InterfaceDescription`
    `Test-NetConnection 8.8.8.8`
    `Test-NetConnection www.microsoft.com -Port 443`
14. **Temperature or throttling**: only if a monitoring tool is already installed (for example the maker's own utility). Do not install one. Otherwise skip and say so.

## Part 2: Conclude

Write a short ranked list of likely causes. Each one gets: the cause in plain English, the evidence line from above that supports it, and how sure you are. Then propose fixes from safest to riskiest. Prefer free, reversible ones (restart, close a program, free disk space) before anything that needs a repair tool. If the evidence points to failing hardware (disk not Healthy, memory errors), say so first and advise backing up before any repair.

## Part 3: Repairs (every one is a CHANGE: restore point, one-line change and undo, typed yes, ledger row, one at a time)

| Repair | Command or step | Undo |
|---|---|---|
| Check system files | `sfc /scannow` (needs an Administrator PowerShell; takes a while) | Only repairs Windows files; no undo needed, but record the result. |
| Repair the Windows image | `DISM /Online /Cleanup-Image /RestoreHealth` (Administrator; needs internet) | Cannot be individually undone; the restore point is the way back. Say so. |
| Disk check, read-only | `chkdsk C: /scan` (this one only reads) | Nothing to undo. |
| Disk repair | `chkdsk C: /f` (schedules a check at next reboot; locks the PC while it runs) | Cannot be undone. Only after a backup and when `/scan` reported errors. |
| Update a driver | Download only from the PC or device maker's official site, tell the owner the address first, install it | Device Manager, device Properties, Driver tab, Roll Back Driver; or the restore point. |
| Disable a startup item | Task Manager, Startup apps tab, right-click, Disable (or disable the one scheduled task) | Enable it again in the same place. |
| Clean temp folders | Delete the contents of `$env:TEMP` only, after listing the size and asking | Cannot be undone. Say so. Skip files in use. |
| Reset the network stack | `netsh winsock reset` then restart | `netsh winsock reset` has no direct undo; the restore point is the way back. Say so. |
| Windows Update repair | Run the built-in troubleshooter: Settings, System, Troubleshoot, Other troubleshooters, Windows Update | Nothing to undo; record the result. |

Do not use registry cleaners, "PC booster" tools, or driver-updater programs. Do not disable Defender, the firewall, or updates.

## Report shape

End with three short sections in plain English:

- **Findings**: what is wrong or likely wrong, and the evidence.
- **Changes**: each change made, and how to undo it (same as in `CHANGES.md`).
- **Watch for**: what to look out for in the next few days, and when to come back.

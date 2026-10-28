---
name: fix-pc
description: Read-only Windows diagnosis runbook, then a ranked list of causes and safe repairs. Use when the owner says "fix my pc", "computer problems", "my computer is slow", "slow", "freezing", "crashing", "blue screen", "won't boot right", "restarts by itself", "diagnose", or "what's wrong with my computer".
---

# /fix-pc: diagnose first, repair only with a restore point and a yes

All commands run in PowerShell on Windows. Part 1 is read-only: run it freely. Part 3 changes the PC: every item needs the `change-ledger` steps (restore point, one-line change and undo, typed yes, ledger row).

First ask the owner: what has been going wrong, since when, and what changed recently. Use the answers to decide which sections of the report matter most. Explain what you find in plain English. If a step errors, note it and move on.

## Part 1: Diagnose (read-only)

Run the collector once, from the kit folder, in this session's own shell (what it prints goes to the signed-in Claude account, as the charter told the owner). It is read-only, needs no Administrator rights, and takes about a minute:

`powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\collect.ps1`

`-ExecutionPolicy Bypass` applies to that one process only; it does not change the PC's setting. The script prints the report and saves it to `reports\collect.txt` in this folder; nothing is sent anywhere. Read the report, then interpret it. Do not re-run its checks by hand.

- A line that says `could not read: <reason>` means that part could not be checked. Tell the owner, and never guess at it. "Access denied" in section 7 (disk counters) is expected without Administrator rights.
- **Windows Update search is opt-in.** The collector does not contact Microsoft by default. If the symptom is about updates, ask the owner first, then add `-SearchForUpdates` (it asks Microsoft which updates are pending, and can take a minute or two).
- Network use otherwise: one ping of the router and one DNS lookup of www.microsoft.com.

### Sections, and how to read them (most likely cause first)

| Section | What to look for |
|---|---|
| 1-2 OS, uptime | Many days up can explain slowness. Only Restart resets the boot time; Shut down then power on does not when Fast Startup is on, so a "recent" boot can hide a long session. |
| 3-4 CPU, RAM, top processes | Free RAM under 10 percent with a few heavy processes is memory pressure. CpuSeconds is total CPU used since the process started, not current load. Name each unfamiliar process in plain English before suggesting anything about it. |
| 5 disk space | Under 10 percent free on C: is a problem by itself. |
| 6-7 disk health | Anything other than Healthy is serious: failing hardware comes first in the ranking, and the owner backs up important files before any repair. A hard disk (HDD) is slow by nature; an SSD upgrade beats any cleanup. |
| 8-9 event errors | The same provider and id repeating. Disk, NTFS, Kernel-Power 41, WHEA or "unexpected shutdown" point at hardware, power or drivers: be conservative. |
| 10 Reliability Monitor | One app crashing repeatedly means that app or its update is broken, not the whole PC. A low stability index shows when things got worse. |
| 11 devices with problems | A missing or broken driver for that device. |
| 12 startup items | A long list plus maker helper suites, a trial antivirus or "PC optimizer" tools is the usual cause of a slow laptop. You may name them; you may not remove or disable security software (see the charter). |
| 13 updates, pending restart | A pending restart is waiting if a reboot-pending line says True: restarting first is the safest fix. "Pending file renames: yes" alone is common on a healthy PC; mention it, but do not treat it as the cause. |
| 14 network | Gateway unreachable or DNS failing: a router or adapter problem; the PC is rarely the cause. |
| 15 install notes | Which tools are present (winget, Git, Python, WSL, Windows Terminal). Context only. |

If the report leaves a question, these targeted read-only checks are allowed, one at a time:
- Crash history: `Get-WinEvent -FilterHashtable @{LogName='System';Id=41,1001,6008;StartTime=(Get-Date).AddDays(-30)} | Select TimeCreated,Id,ProviderName,Message` (41 = restarted without a clean shutdown, 1001 = a crash report was made, 6008 = the previous shutdown was unexpected).
- Crash dumps: `Get-ChildItem C:\Windows\Minidump | Select Name,Length,LastWriteTime`. "Access is denied" means the folder needs Administrator to read, NOT that there are no crashes: say so and rely on the event check. "Cannot find path" means no dumps were saved. Do not open or send the files anywhere.
- Drivers (display, network, storage): `Get-CimInstance Win32_PnPSignedDriver | Where DeviceClass -in 'DISPLAY','NET','SCSIADAPTER','HDC' | Select DeviceName,DriverVersion,DriverDate`. Note drivers older than two years or dated right before the problem began.
- Temperature or throttling: only if a monitoring tool is already installed. Do not install one.

## Part 2: Conclude

Write a short ranked list of likely causes. Each one gets: the cause in plain English, the evidence line from the report that supports it, and how sure you are. Then propose fixes from safest to riskiest. Prefer free, reversible ones (restart, close a program, free disk space) before anything that needs a repair tool. If the evidence points to failing hardware (disk not Healthy, memory errors), say so first and advise backing up before any repair.

## Part 3: Repairs (every one is a CHANGE: restore point, one-line change and undo, typed yes, ledger row, one at a time)

Act, do not instruct: after the yes, run it.

### Restore point and safety net (once, before the first change)

After the owner's typed yes to the first change, run `scripts\safety.ps1` in an Administrator window. It makes the System Restore point, exports the startup-related registry keys and writes a baseline of installed programs, services and startup items, all into `backups\` in this folder, and it records its result in `backups\safety-result.txt`.

1. Make a new run id: `$run = [guid]::NewGuid().ToString()`, and write the id down in your reply (shell variables may not survive between your tool calls; use the literal id then). First, in this session (not elevated), export the owner's own startup keys, because an Administrator window may belong to a different account: `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\safety.ps1 -ExportHkcuOnly -RunId $run`. If its exit code is not 0, stop.
2. Tell the owner a Windows "allow this app to make changes" box will appear and to click Yes, and that the new window closes by itself when it finishes. Then run, with the full path to this folder in place of `<kit folder>` (the embedded double quotes keep a path with spaces in one piece):
   `Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','"<kit folder>\scripts\safety.ps1"','-RunId',$run`
3. Ask the owner to say when the window has gone, then read the first line of `backups\safety-result.txt`. **Only a line that starts `OK RunId=` followed by this run's id counts as success.** Anything else is not success: `RUNNING` (not finished), `STOP`, an OK with a different id (left over from an earlier run), or a missing file (the window never started, for example the box was declined). Never delete or edit that file yourself.
4. **If it is not that OK line: stop the run.** Tell the owner plainly what it said and make no change. Never continue "because it is a small change".
   - System Protection off: ask for a separate yes, add the ledger row for turning it on FIRST (the `change-ledger` steps; no restore point can cover this one step, so say so to the owner when you ask), then repeat from step 1 with a new run id and `'-EnableSystemProtection'` added to the argument list.
   - Windows allows one restore point per 24 hours. The STOP line lists the restore points from the last 24 hours with their dates. Give the owner the date and ask for a separate yes before repeating from step 1 with a new run id and `'-UseExistingRestorePoint'` added.
5. On that OK, go on with the `change-ledger` steps for this change. The restore point covers the whole session; do not make a second one.

This session is NOT running as Administrator, so `sfc`, `DISM`, `chkdsk` and `netsh` fail here. Run each one in its own Administrator window that stays open, so the owner can read it. Tell the owner a Windows "allow this app to make changes" box will appear and to click Yes, then run `Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile','-NoExit','-Command','<command>'`. Do not wait on that window. Ask the owner to say when it finishes and read you the last lines; the owner closes the window afterwards.

| Repair | Command or step | Undo |
|---|---|---|
| Check system files | `sfc /scannow` (Administrator window; 10 to 30 minutes) | Only repairs Windows files; no undo needed, but record the result. |
| Repair the Windows image | `DISM /Online /Cleanup-Image /RestoreHealth` (Administrator window; needs internet; 10 to 30 minutes and can sit on one percentage for a long time, do not close it) | Cannot be individually undone; the restore point is the way back. Say so. |
| Disk check, read-only | `chkdsk C: /scan` in an Administrator window (only reads; a few minutes). Not a change: no restore point or ledger row, but still ask first. | Nothing to undo. |
| Disk repair | `chkdsk C: /f` in an Administrator window. It asks to schedule the check for the next restart (Y/N), and the owner types Y in that window. The check runs at the next restart, before Windows loads, and can take an hour or more. The owner restarts when ready. | Cannot be undone. Only after a backup and when `/scan` reported errors. |
| Update a driver | Download only from the PC or device maker's official site, tell the owner the address first, install it | Device Manager, device Properties, Driver tab, Roll Back Driver; or the restore point. |
| Disable a startup item | Task Manager, Startup apps tab, right-click, Disable (or disable the one scheduled task) | Enable it again in the same place. |
| Clean temp folders | Run the guarded block under this table: it lists the size first (ask, then run it again with deleting on) | Cannot be undone. Say so. |
| Reset the network stack | `netsh winsock reset` in an Administrator window, then the owner restarts the PC when ready | `netsh winsock reset` has no direct undo; the restore point is the way back. Say so. |
| Windows Update repair | Run the built-in troubleshooter: Settings, System, Troubleshoot, Other troubleshooters, Windows Update | Nothing to undo; record the result. |

Guarded temp cleanup (the first run only counts and reports; after the owner's yes, run it again with `$delete = $true`). It refuses unless `$env:TEMP` is an existing folder named Temp or Tmp under the user's profile or Windows, and it skips links (junctions and symlinks) rather than following them. Files in use are skipped and reported.

```
$delete = $false
$t = $env:TEMP
$ok = [bool]$t -and (Test-Path -LiteralPath $t -PathType Container)
if ($ok) {
    $t = (Get-Item -LiteralPath $t).FullName.TrimEnd('\')
    $ok = (@('Temp', 'Tmp') -contains (Split-Path -Leaf $t)) -and ($t.StartsWith($env:USERPROFILE + '\', [StringComparison]::OrdinalIgnoreCase) -or $t.StartsWith($env:SystemRoot + '\', [StringComparison]::OrdinalIgnoreCase))
}
if (-not $ok) { throw 'Refusing: TEMP is empty, missing, or not a Temp folder under the user profile or Windows.' }
$script:bytes = 0
function Clear-Walk([string]$Dir) {
    foreach ($i in Get-ChildItem -LiteralPath $Dir -Force) {
        if (($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { "skipped link: $($i.FullName)"; continue }
        if ($i.PSIsContainer) { Clear-Walk $i.FullName; if ($delete) { Remove-Item -LiteralPath $i.FullName -ErrorAction Continue } }
        else { $script:bytes += $i.Length; if ($delete) { Remove-Item -LiteralPath $i.FullName -Force -ErrorAction Continue } }
    }
}
Clear-Walk $t
"{0} MB in {1}" -f [math]::Round($script:bytes / 1MB), $t
```

Do not use registry cleaners, "PC booster" tools, or driver-updater programs. Do not disable Defender, the firewall, or updates.

## Report shape

End with three short sections in plain English:

- **Findings**: what is wrong or likely wrong, and the evidence.
- **Changes**: each change made, and how to undo it (same as in `CHANGES.md`).
- **Watch for**: what to look out for in the next few days, and when to come back.

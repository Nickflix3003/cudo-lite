<#
.SYNOPSIS
  Safety net to run BEFORE the first change: restore point, startup-key export, baseline (Cudo Lite).
.DESCRIPTION
  Two steps, both started by the assistant with the same -RunId (a new GUID per attempt):
  A. In the assistant's own, NON-elevated session: -ExportHkcuOnly exports the current user's
     startup keys to <kit folder>\backups\. This must happen before elevating, because an
     Administrator window may belong to a different account whose HKCU is not the owner's.
  B. In an Administrator window the owner clicked open:
     1. (only with -EnableSystemProtection, which the owner must have said yes to)
        turns on System Protection for the system drive.
     2. Creates a System Restore point (or, with -UseExistingRestorePoint and the owner's yes,
        accepts one made in the last 24 hours). If that fails for any reason, this script
        prints a plain message and exits non-zero. Callers must stop and tell the owner.
     3. Exports the machine-wide Run keys (and the Task Manager startup on/off keys).
     4. Writes a baseline text file there: installed programs, services, startup items.
     5. Writes <kit folder>\backups\safety-result.txt as RUNNING, then OK or STOP with the
        reason. Every line starts with the state and carries RunId=<the id>. The assistant
        accepts only an OK carrying the id it passed in, because the Administrator window
        is not the assistant's own shell and an older OK must never be read as this run's.
  Needs an Administrator window for step B. Supports -WhatIf.
  Exit codes: 0 ok, 2 restore point failed, 3 not administrator, 4 backup failed or bad arguments.
  The kit folder is the parent of this scripts folder (override with -KitDir for tests).
.PARAMETER RunId
  A GUID the caller made for this attempt. Required (except with -WhatIf).
.PARAMETER ExportHkcuOnly
  Step A above. Needs no Administrator rights and makes no restore point.
.PARAMETER UseExistingRestorePoint
  Windows allows one new restore point per 24 hours. With the owner's yes, accept a
  restore point made in the last 24 hours instead of creating a new one.
#>
[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    [string]$RunId,
    [switch]$ExportHkcuOnly,
    [switch]$EnableSystemProtection,
    [switch]$UseExistingRestorePoint,
    [string]$KitDir = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$description = "Cudo Lite before changes $stamp"
$backup = Join-Path $KitDir 'backups'
$resultFile = Join-Path $backup 'safety-result.txt'
$regExe = Join-Path $env:SystemRoot 'System32\reg.exe'

function Write-Result {
    param([string]$State, [string]$Text = '')
    $id = if ($RunId) { $RunId } else { 'none' }
    try {
        if (-not (Test-Path -LiteralPath $backup)) { New-Item -ItemType Directory -Path $backup -Force | Out-Null }
        Set-Content -LiteralPath $resultFile -Value ("$State RunId=$id $Text").Trim() -Encoding UTF8
    }
    catch { Write-Host "Could not write $resultFile : $($_.Exception.Message)" }
}

function Get-RecentPointsText {
    try {
        $cut = (Get-Date).AddHours(-24)
        $recent = @(Get-ComputerRestorePoint | Where-Object { [Management.ManagementDateTimeConverter]::ToDateTime($_.CreationTime) -ge $cut })
        if ($recent.Count -eq 0) { return 'Restore points from the last 24 hours: none.' }
        $items = $recent | Sort-Object SequenceNumber | ForEach-Object { "$([Management.ManagementDateTimeConverter]::ToDateTime($_.CreationTime).ToString('yyyy-MM-dd HH:mm')) $($_.Description)" }
        return 'Restore points from the last 24 hours: ' + ($items -join '; ') + '.'
    }
    catch { return "Restore points from the last 24 hours: could not read ($($_.Exception.Message))." }
}

function Stop-Loud {
    param([int]$Code, [string]$Message)
    if ($Code -eq 2) { $Message = "$Message $(Get-RecentPointsText)" }
    Write-Host ''
    Write-Host "STOP: $Message"
    Write-Host 'No changes should be made to this PC until this is sorted out. Tell the owner what happened.'
    Write-Result 'STOP' "code=$Code $Message"
    exit $Code
}

# Tests define Test-IsAdmin to stand in for an Administrator window; a fresh elevated PowerShell has no such function.
if (-not (Test-Path -LiteralPath 'Function:\Test-IsAdmin')) {
    function Test-IsAdmin {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
}

$keys = @(
    @{ Hive = 'HKCU'; Key = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run'; Name = 'hkcu-run' },
    @{ Hive = 'HKLM'; Key = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Run'; Name = 'hklm-run' },
    @{ Hive = 'HKLM'; Key = 'HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Name = 'hklm-wow6432-run' },
    @{ Hive = 'HKCU'; Key = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Name = 'hkcu-startupapproved-run' },
    @{ Hive = 'HKLM'; Key = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Name = 'hklm-startupapproved-run' },
    @{ Hive = 'HKCU'; Key = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'; Name = 'hkcu-startupapproved-run32' },
    @{ Hive = 'HKLM'; Key = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'; Name = 'hklm-startupapproved-run32' },
    @{ Hive = 'HKCU'; Key = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'; Name = 'hkcu-startupapproved-folder' },
    @{ Hive = 'HKLM'; Key = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'; Name = 'hklm-startupapproved-folder' }
)

function Export-Keys {
    param([string]$Hive, [string]$Suffix)
    $done = New-Object System.Collections.Generic.List[string]
    foreach ($item in ($keys | Where-Object { $_.Hive -eq $Hive })) {
        $keyPath = $item.Key
        if (-not (Test-Path -LiteralPath ('Registry::' + $keyPath))) { Write-Host "Registry key not present, nothing to export: $keyPath"; continue }
        $file = Join-Path $backup "$($item.Name)-$Suffix.reg"
        & $regExe export $keyPath $file /y | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $file)) {
            Stop-Loud 4 "Could not export the registry key $keyPath to $file."
        }
        Write-Host "Exported $keyPath -> $file"
        $done.Add($keyPath)
    }
    $done
}

if (-not $PSCmdlet.ShouldProcess('System Restore point and backups', 'Create')) {
    Write-Host "What-if only, nothing was done (this is NOT a success): would create a restore point named '$description', export the startup keys and write a baseline under $backup."
    exit 0
}

if ($RunId -notmatch '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') {
    $RunId = ''
    Stop-Loud 4 'A valid -RunId (a new GUID for this attempt) is required.'
}

try {
    if (-not (Test-Path -LiteralPath $regExe)) { Stop-Loud 4 "reg.exe was not found at $regExe." }
    try { New-Item -ItemType Directory -Path $backup -Force | Out-Null }
    catch { Stop-Loud 4 "Could not create the backup folder $backup : $($_.Exception.Message)" }

    if ($ExportHkcuOnly) {
        $exported = @(Export-Keys 'HKCU' $RunId)
        Set-Content -LiteralPath (Join-Path $backup "hkcu-done-$RunId.txt") -Value ($exported -join "`r`n") -Encoding UTF8
        Write-Host "Current-user startup keys exported ($($exported.Count) keys)."
        exit 0
    }

    if (-not (Test-IsAdmin)) {
        Stop-Loud 3 'This step needs an Administrator window (a restore point cannot be made without one). Open it with Start-Process -Verb RunAs and ask the owner to click Yes.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $backup "hkcu-done-$RunId.txt"))) {
        Stop-Loud 4 'The current user''s startup keys were not exported first for this run (run this script with -ExportHkcuOnly and the same -RunId in the assistant''s own session, before opening the Administrator window).'
    }
    Write-Result 'RUNNING'

    if ($EnableSystemProtection) {
        try { Enable-ComputerRestore -Drive "$env:SystemDrive\" }
        catch { Stop-Loud 2 "Could not turn on System Protection: $($_.Exception.Message)" }
        Write-Host "System Protection turned on for $env:SystemDrive\ (undo: System Properties > System Protection > Configure > Turn off)."
    }

    $ok = $false
    $why = ''
    try {
        if ($UseExistingRestorePoint) {
            $cut = (Get-Date).AddHours(-24)
            $recent = @(Get-ComputerRestorePoint | Where-Object { [Management.ManagementDateTimeConverter]::ToDateTime($_.CreationTime) -ge $cut })
            if ($recent.Count -gt 0) {
                $last = $recent | Sort-Object SequenceNumber | Select-Object -Last 1
                $description = "$($last.Description) (existing, made $([Management.ManagementDateTimeConverter]::ToDateTime($last.CreationTime)))"
                $ok = $true
            }
            else { $why = 'No restore point from the last 24 hours exists.' }
        }
        else {
            Checkpoint-Computer -Description $description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
            Start-Sleep -Seconds 2
            # Checkpoint-Computer only warns when Windows refuses a second point within 24 hours, so verify it exists.
            $made = @(Get-ComputerRestorePoint | Where-Object { $_.Description -eq $description })
            $ok = ($made.Count -gt 0)
            if (-not $ok) { $why = 'Windows did not report a new restore point (System Protection may be off for this drive, or one was already made in the last 24 hours).' }
        }
    }
    catch { $why = $_.Exception.Message }

    if (-not $ok) {
        Stop-Loud 2 "Could not create a System Restore point. $why Ask the owner whether to turn on System Protection (a separate yes), or whether to accept a restore point from the last 24 hours."
    }
    Write-Host "Restore point ready: $description"

    $null = Export-Keys 'HKLM' $stamp

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Cudo Lite baseline taken $stamp (read-only snapshot, kept in this folder)")
    function Add-Part {
        param([string]$Title, [scriptblock]$Body)
        $lines.Add(''); $lines.Add("=== $Title ===")
        try { $lines.Add(((& $Body | Out-String -Width 220).TrimEnd())) }
        catch { $lines.Add("could not read: $($_.Exception.Message)") }
    }
    Add-Part 'Installed programs' {
        $paths = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        Get-ItemProperty $paths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } |
            Select-Object DisplayName, DisplayVersion, Publisher | Sort-Object DisplayName | Format-Table -AutoSize
    }
    Add-Part 'Services (state and start type)' {
        Get-CimInstance Win32_Service | Sort-Object Name | Select-Object Name, State, StartMode | Format-Table -AutoSize
    }
    Add-Part 'Startup items' {
        Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User | Format-Table -AutoSize -Wrap
    }
    $baseFile = Join-Path $backup "baseline-$stamp.txt"
    try { Set-Content -LiteralPath $baseFile -Value $lines -Encoding UTF8 }
    catch { Stop-Loud 4 "Could not write the baseline file $baseFile : $($_.Exception.Message)" }
    Write-Host "Baseline written: $baseFile"

    Write-Result 'OK' "restore point '$description'; backups in $backup"
    Write-Host ''
    Write-Host "Safety net ready. Restore point: '$description'. Backups: $backup"
    exit 0
}
catch {
    Stop-Loud 4 "Unexpected error, nothing further was done: $($_.Exception.Message)"
}

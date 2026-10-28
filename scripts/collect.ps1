<#
.SYNOPSIS
  Read-only PC health collector for Windows PowerShell 5.1 (Cudo Lite).
.DESCRIPTION
  Gathers facts about this PC and writes a readable text report to
  <kit folder>\reports\collect.txt (the kit folder is the parent of this scripts
  folder), then prints it. It changes nothing on the PC and sends no report data
  anywhere; the assistant reads the printed report in its own session. Network use is limited
  to a ping of the router and one DNS lookup; the Windows Update search (which contacts
  Microsoft) runs only with -SearchForUpdates. Every section is wrapped so a failure
  shows up as "could not read: <reason>" instead of being hidden. Administrator rights
  are not required; a few sections give more detail when run as administrator.
.PARAMETER OutDir
  Where collect.txt is written. Defaults to the reports folder inside the kit folder.
.PARAMETER SearchForUpdates
  Also ask Microsoft which updates are pending. Only with the owner's yes.
#>
[CmdletBinding()]
param(
    [string]$OutDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'reports'),
    [switch]$SearchForUpdates
)

$script:Report = New-Object System.Collections.Generic.List[string]

function Add-Section {
    param([string]$Title, [scriptblock]$Body)
    $script:Report.Add('')
    $script:Report.Add("=== $Title ===")
    $buf = New-Object System.Collections.ArrayList
    $err = $null
    try {
        $ErrorActionPreference = 'Stop'
        & $Body | ForEach-Object { [void]$buf.Add($_) }
    }
    catch { $err = $_.Exception.Message }
    # Keep whatever was read before a failure, then say what could not be read.
    $text = ($buf | Out-String -Width 200).TrimEnd()
    if ($err) { $text = ($text + "`r`ncould not read: $err").TrimStart() }
    if ([string]::IsNullOrWhiteSpace($text)) { $text = '(nothing to report)' }
    $script:Report.Add($text)
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-EventSummary {
    param([string]$LogName)
    $since = (Get-Date).AddDays(-14)
    try {
        $ev = Get-WinEvent -FilterHashtable @{ LogName = $LogName; Level = 1, 2; StartTime = $since } -MaxEvents 5000 -ErrorAction Stop
    }
    catch {
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { return 'No error or critical events in the last 14 days.' }
        throw
    }
    $ev | Group-Object ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 20 |
        ForEach-Object {
            $first = $_.Group[0]
            $msg = ''
            if ($first.Message) { $msg = ($first.Message -split "`r?`n")[0]; if ($msg.Length -gt 110) { $msg = $msg.Substring(0, 110) } }
            [pscustomobject]@{ Count = $_.Count; Source = $first.ProviderName; Id = $first.Id; Example = $msg }
        } | Format-Table -AutoSize -Wrap
}

$started = Get-Date
$script:Report.Add('Cudo Lite collection report (read-only)')
$script:Report.Add("Collected: $($started.ToString('yyyy-MM-dd HH:mm:ss')) as user $env:USERNAME, administrator: $(Test-IsAdmin)")
$script:Report.Add("PowerShell: $($PSVersionTable.PSVersion)")

Add-Section '1. OS and edition' {
    $os = Get-CimInstance Win32_OperatingSystem
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    [pscustomobject]@{
        Caption = $os.Caption; Edition = $cv.EditionID; Version = $cv.DisplayVersion
        Build = "$($os.BuildNumber).$($cv.UBR)"; Arch = $os.OSArchitecture; InstallDate = $os.InstallDate
    } | Format-List
    $cs = Get-CimInstance Win32_ComputerSystem
    "Maker/model: $($cs.Manufacturer) $($cs.Model)"
}

Add-Section '2. Uptime' {
    $os = Get-CimInstance Win32_OperatingSystem
    $up = (Get-Date) - $os.LastBootUpTime
    "Last boot: $($os.LastBootUpTime)"
    "Up for: {0} days {1} hours {2} minutes" -f $up.Days, $up.Hours, $up.Minutes
}

Add-Section '3. CPU and RAM' {
    Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed, LoadPercentage | Format-List
    $os = Get-CimInstance Win32_OperatingSystem
    $totalMB = [math]::Round($os.TotalVisibleMemorySize / 1024)
    $freeMB = [math]::Round($os.FreePhysicalMemory / 1024)
    "RAM total: $totalMB MB, free: $freeMB MB ({0}% free)" -f [math]::Round(100 * $freeMB / $totalMB)
}

Add-Section '4. Top processes (by memory, then by CPU)' {
    'Top 12 by memory:'
    (Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 12 Name, Id,
        @{ n = 'MemMB'; e = { [math]::Round($_.WorkingSet / 1MB) } },
        @{ n = 'CpuSeconds'; e = { [math]::Round($_.CPU) } } | Format-Table -AutoSize | Out-String -Width 200).TrimEnd()
    ''
    'Top 10 by CPU (total CPU seconds since each process started, not current load):'
    (Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 Name, Id,
        @{ n = 'CpuSeconds'; e = { [math]::Round($_.CPU) } },
        @{ n = 'MemMB'; e = { [math]::Round($_.WorkingSet / 1MB) } } | Format-Table -AutoSize | Out-String -Width 200).TrimEnd()
}

Add-Section '5. Disks: free space' {
    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Select-Object DeviceID, VolumeName,
        @{ n = 'SizeGB'; e = { [math]::Round($_.Size / 1GB, 1) } },
        @{ n = 'FreeGB'; e = { [math]::Round($_.FreeSpace / 1GB, 1) } },
        @{ n = 'PctFree'; e = { if ($_.Size) { [math]::Round(100 * $_.FreeSpace / $_.Size) } } } | Format-Table -AutoSize
}

Add-Section '6. Disks: health' {
    Get-PhysicalDisk | Select-Object FriendlyName, MediaType, BusType, HealthStatus, OperationalStatus,
        @{ n = 'SizeGB'; e = { [math]::Round($_.Size / 1GB) } } | Format-Table -AutoSize
}

Add-Section '7. Disks: reliability counters (SMART-style, may need administrator)' {
    Get-PhysicalDisk | ForEach-Object {
        $d = $_
        try {
            $c = $d | Get-StorageReliabilityCounter -ErrorAction Stop
            [pscustomobject]@{ Disk = $d.FriendlyName; TempC = $c.Temperature; Wear = $c.Wear; ReadErrors = $c.ReadErrorsTotal; WriteErrors = $c.WriteErrorsTotal; PowerOnHours = $c.PowerOnHours }
        }
        catch { [pscustomobject]@{ Disk = $d.FriendlyName; TempC = "could not read: $($_.Exception.Message)"; Wear = $null; ReadErrors = $null; WriteErrors = $null; PowerOnHours = $null } }
    } | Format-Table -AutoSize -Wrap
}

Add-Section '8. System event errors, last 14 days (top 20 by source and id)' { Get-EventSummary 'System' }

Add-Section '9. Application event errors, last 14 days (top 20 by source and id)' { Get-EventSummary 'Application' }

Add-Section '10. Reliability Monitor, last 14 days' {
    $since = (Get-Date).AddDays(-14)
    $recs = Get-CimInstance Win32_ReliabilityRecords | Where-Object { $_.TimeGenerated -ge $since }
    if (-not $recs) { 'No reliability records in the last 14 days.' }
    else {
        $recs | Sort-Object TimeGenerated -Descending | Select-Object -First 40 TimeGenerated, SourceName, EventIdentifier,
            @{ n = 'Message'; e = { $m = ($_.Message -split "`r?`n")[0]; if ($m -and $m.Length -gt 100) { $m.Substring(0, 100) } else { $m } } } | Format-Table -AutoSize -Wrap
    }
    try {
        $idx = Get-CimInstance Win32_ReliabilityStabilityMetrics | Where-Object { $_.StartMeasurementDate -ge $since } |
            Sort-Object StartMeasurementDate | Select-Object -Last 14 StartMeasurementDate, SystemStabilityIndex
        if ($idx) { 'Stability index (10 is best):'; $idx | Format-Table -AutoSize }
    }
    catch { "Stability index: could not read: $($_.Exception.Message)" }
}

Add-Section '11. Devices with problems' {
    $bad = @(Get-PnpDevice -PresentOnly | Where-Object { $_.Status -ne 'OK' -and $_.Status -ne 'Unknown' })
    if ($bad.Count -eq 0) { 'No present devices report a problem.' }
    else { $bad | Select-Object FriendlyName, Class, Status, Problem, InstanceId | Format-Table -AutoSize -Wrap }
}

Add-Section '12. Startup items (read only)' {
    'Win32_StartupCommand:'
    Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User | Format-Table -AutoSize -Wrap
    foreach ($k in 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run') {
        "Run key $k"
        try {
            if (Test-Path $k) {
                $p = Get-ItemProperty $k
                $p.PSObject.Properties | Where-Object { 'PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider' -notcontains $_.Name } | ForEach-Object { "  $($_.Name) = $($_.Value)" }
            }
            else { '  (key not present)' }
        }
        catch { "  could not read: $($_.Exception.Message)" }
    }
    'Counts:'
    "  Running services: $(@(Get-Service | Where-Object Status -eq 'Running').Count)"
    try { "  Scheduled tasks in Ready state: $(@(Get-ScheduledTask | Where-Object State -eq 'Ready').Count)" } catch { "  Scheduled tasks: could not read: $($_.Exception.Message)" }
    try { $ws = Get-Service WSearch; "  Windows Search service: $($ws.Status)" } catch { "  Windows Search service: could not read: $($_.Exception.Message)" }
}

Add-Section '13. Windows Update and pending restart' {
    $flags = @(
        @{ n = 'CBS reboot pending'; k = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending' },
        @{ n = 'Windows Update reboot required'; k = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' }
    )
    foreach ($f in $flags) { "$($f.n): $(Test-Path $f.k)" }
    $pfr = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction Stop).PendingFileRenameOperations
    "Pending file renames: $(if ($pfr) { 'yes' } else { 'no' })"
    "Windows Update service: $((Get-Service wuauserv).Status)"
    'Last installed updates:'
    Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 8 HotFixID, Description, InstalledOn | Format-Table -AutoSize
    if (-not $SearchForUpdates) { 'Pending update search: not run (it contacts Microsoft; add -SearchForUpdates if the owner agrees).' }
    else {
        $job = Start-Job -ScriptBlock {
            $s = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
            $r = $s.Search('IsInstalled=0 and IsHidden=0')
            "Pending updates found: $($r.Updates.Count)"
            foreach ($u in $r.Updates) { "  - $($u.Title)" }
        }
        try {
            if (Wait-Job $job -Timeout 90) {
                try { Receive-Job $job -ErrorAction Stop } catch { "Pending update search: could not read: $($_.Exception.Message)" }
            }
            else { Stop-Job $job; 'Pending update search: could not read: timed out after 90 seconds' }
        }
        finally { Remove-Job $job -Force -ErrorAction SilentlyContinue }
    }
}

Add-Section '14. Network' {
    Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object Name, InterfaceDescription, LinkSpeed | Format-Table -AutoSize -Wrap
    $gws = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Where-Object { $_.NextHop -ne '0.0.0.0' })
    if ($gws.Count -gt 0) {
        foreach ($gw in $gws) { "Default gateway $($gw.NextHop) via $($gw.InterfaceAlias): reachable $(Test-Connection -ComputerName $gw.NextHop -Count 2 -Quiet)" }
    }
    else { 'Default gateway: none found' }
    try { $a = [System.Net.Dns]::GetHostAddresses('www.microsoft.com'); "DNS resolve www.microsoft.com: ok ($($a.Count) addresses)" }
    catch { "DNS resolve www.microsoft.com: FAILED ($($_.Exception.Message))" }
}

Add-Section '15. Install notes (what is on this PC)' {
    $os = Get-CimInstance Win32_OperatingSystem
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    "Windows: $($os.Caption), edition $($cv.EditionID), version $($cv.DisplayVersion), build $($os.BuildNumber).$($cv.UBR)"
    "Administrator session: $(Test-IsAdmin)"
    $c = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
    "Free disk on $($env:SystemDrive): $([math]::Round($c.FreeSpace / 1GB, 1)) GB of $([math]::Round($c.Size / 1GB, 1)) GB"
    function Show-Tool([string]$Label, [string[]]$Names, [string[]]$VersionArgs) {
        $cmd = $null
        foreach ($n in $Names) { $cmd = Get-Command $n -ErrorAction SilentlyContinue | Select-Object -First 1; if ($cmd) { break } }
        if (-not $cmd) { return "${Label}: not found" }
        $line = "${Label}: found at $($cmd.Source)"
        if ($cmd.Source -like '*\WindowsApps\*' -and $Label -eq 'Python') { $line += ' (may be only the Microsoft Store shortcut, not a real install)' }
        elseif ($VersionArgs) { try { $v = (& $cmd.Source @VersionArgs 2>&1 | Select-Object -First 1); $line += " ($v)" } catch { $line += ' (version unreadable)' } }
        $line
    }
    Show-Tool 'winget' @('winget') @('--version')
    Show-Tool 'Git' @('git') @('--version')
    Show-Tool 'Python' @('python', 'py') $null
    Show-Tool 'WSL' @('wsl') $null
    $wt = Get-Command wt -ErrorAction SilentlyContinue
    $wtPkg = $null
    try { $wtPkg = Get-AppxPackage -Name Microsoft.WindowsTerminal -ErrorAction Stop } catch { $wtPkg = $null }
    "Windows Terminal: $(if ($wt -or $wtPkg) { 'present' } else { 'not found' })"
}

$script:Report.Add('')
$script:Report.Add("=== End of report (took $([int]((Get-Date) - $started).TotalSeconds) seconds). Read-only: nothing was changed and this script sent no report data anywhere (the assistant reads the report in its own session). Network use: a ping to the router and one DNS lookup, plus the update check only if asked. ===")

$outFile = Join-Path $OutDir 'collect.txt'
$saveNote = ''
try {
    if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force -ErrorAction Stop | Out-Null }
    Set-Content -LiteralPath $outFile -Value $script:Report -Encoding UTF8 -ErrorAction Stop
    $saveNote = "Report saved to: $outFile"
}
catch { $saveNote = "Report NOT saved: $($_.Exception.Message)" }
$script:Report
$saveNote
if ($saveNote -like 'Report NOT saved*') { exit 1 }

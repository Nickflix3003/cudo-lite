# Plain PowerShell asserts for Cudo Lite. Exit code is non-zero if any check fails.
# Runs against throwaway fake kit folders under %TEMP%. safety.ps1 runs with Checkpoint-Computer and
# Get-ComputerRestorePoint stubbed as functions; the real ones are never called. collect.ps1 runs for real (read-only).
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $env:TEMP
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$ps = Join-Path $PSHOME 'powershell.exe'
$root = Join-Path $env:TEMP ('cudo-lite-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$script:fail = 0
$script:pass = 0

function Check {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) { $script:pass++; Write-Host "PASS: $Name" }
    else { $script:fail++; Write-Host "FAIL: $Name $Detail" }
}
function New-Kit {
    param([string]$Name)
    $p = Join-Path $root $Name
    New-Item -ItemType Directory -Path $p | Out-Null
    $p
}
function Invoke-Script {
    param([string]$File, [string[]]$Arguments)
    $ErrorActionPreference = 'Continue'
    $out = & $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $File @Arguments 2>&1 | Out-String
    [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
}
function Get-Tree {
    param([string]$Dir)
    @(Get-ChildItem -LiteralPath $Dir -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName } | Sort-Object)
}

try {
    # 0. The kit's shape: folder-local, no installer, no writes to the user's .claude.
    foreach ($f in 'CLAUDE.md', 'README.md', 'LICENSE', 'NOTICE', 'INSTALL-PROMPT.md', '.claude\skills\fix-pc\SKILL.md', '.claude\skills\change-ledger\SKILL.md', 'scripts\collect.ps1', 'scripts\safety.ps1', 'scripts\log-fix.ps1') {
        Check "kit has $f" (Test-Path -LiteralPath (Join-Path $repo $f))
    }
    Check 'kit has no install.ps1' (-not (Test-Path -LiteralPath (Join-Path $repo 'install.ps1')))
    $scripts = @(Get-ChildItem -LiteralPath (Join-Path $repo 'scripts') -Filter '*.ps1' -File)
    $userClaude = @($scripts | Where-Object { (Get-Content -LiteralPath $_.FullName) | Where-Object { $_ -notmatch '^\s*#' -and $_ -match 'USERPROFILE.{0,20}\.claude|\.claude\\(skills|settings)' } })
    Check 'scripts never write to a user .claude folder' ($userClaude.Count -eq 0) (($userClaude | ForEach-Object Name) -join ',')

    # 1. collect.ps1 is read-only and complete.
    $coll = Join-Path $repo 'scripts\collect.ps1'
    $code = (Get-Content -LiteralPath $coll) | Where-Object { $_ -notmatch '^\s*#' }
    $forbidden = '\b(Remove-(?!Job\b)\w+|Set-ItemProperty|New-ItemProperty|Stop-Service|Start-Service|Restart-Service|Set-Service|Disable-\w+|Enable-\w+|Uninstall-\w+|Set-ExecutionPolicy|Checkpoint-Computer|Restore-Computer|Invoke-WebRequest|Invoke-RestMethod|Start-BitsTransfer|Set-MpPreference|Stop-Process|Clear-\w+|Move-Item|Copy-Item|Rename-Item|Install-\w+)\b|\breg(\.exe)?\s+(add|delete|import)\b|\b(sfc|dism|cleanmgr)\b'
    $hits = @($code | Where-Object { $_ -match $forbidden })
    Check 'collect.ps1 contains no change or upload commands' ($hits.Count -eq 0) ($hits -join ' || ')
    $p1 = New-Kit 'collect'
    $outDir = Join-Path $p1 'out'
    $r = Invoke-Script $coll @('-OutDir', $outDir)
    Check 'collect.ps1 exits 0' ($r.Code -eq 0) $r.Out
    $txt = Join-Path $outDir 'collect.txt'
    Check 'collect.txt written' (Test-Path -LiteralPath $txt)
    $body = ''
    if (Test-Path -LiteralPath $txt) { $body = [IO.File]::ReadAllText($txt) }
    $titles = '1. OS and edition', '2. Uptime', '3. CPU and RAM', '4. Top processes', '5. Disks: free space', '6. Disks: health', '7. Disks: reliability counters',
        '8. System event errors', '9. Application event errors', '10. Reliability Monitor', '11. Devices with problems', '12. Startup items',
        '13. Windows Update and pending restart', '14. Network', '15. Install notes'
    foreach ($t in $titles) { Check "collect.txt has section '$t'" ($body.Contains("=== $t")) }
    Check 'collect.ps1 wrote only into -OutDir' ((Get-Tree $p1).Count -eq 2 -and (Test-Path (Join-Path $p1 'out')))
    Check 'collect.ps1 does not contact Windows Update by default' ($body -match 'Pending update search: not run')
    Check 'collect.txt has a top-10 by CPU list' ($body.Contains('Top 10 by CPU'))
    Check 'collect.ps1 looks back 14 days for events and removes its update-search job' ($body -match 'System event errors, last 14 days' -and ($code -join "`n") -match 'AddDays\(-14\)' -and ($code -join "`n") -match 'Remove-Job')
    Write-Host ("INFO: sections that report 'could not read': " + ([regex]::Matches($body, 'could not read')).Count)

    # 2. log-fix.ps1 appends a row (with its undo) to CHANGES.md, the change-ledger file.
    # The skill runs it IN-PROCESS (powershell -File mangles double quotes on 5.1), so the exact-text tests do the same.
    $lf = Join-Path $repo 'scripts\log-fix.ps1'
    function Invoke-LogFix {
        param([hashtable]$Params)
        try { $o = & $lf @Params *>&1 | Out-String; [pscustomobject]@{ Code = 0; Out = $o } }
        catch { [pscustomobject]@{ Code = 1; Out = $_.Exception.Message } }
    }
    function Read-Row {
        param([string]$Row)   # split on unescaped pipes, then un-escape \| back to a pipe
        $cells = [regex]::Split($Row, '(?<!\\)\|')
        @($cells[1..($cells.Count - 2)] | ForEach-Object { $_.Trim() -replace '\\\|', '|' })
    }
    $p2 = New-Kit 'logfix'
    $what = 'Disabled "Foo Helper" | startup, it''s $5'
    $cmdText = 'reg add "HKCU\Software\X" /v "A B" /d "1" | Out-Null; echo "done" $env:TEMP'
    $undoText = 'Re-enable "Foo Helper" | in Task Manager > Startup apps; reg delete "HKCU\Software\X" /v "A B" /f'
    $r = Invoke-LogFix @{ What = $what; Command = $cmdText; Undo = $undoText; KitDir = $p2 }
    $ledger = Join-Path $p2 'CHANGES.md'
    $logLines = @()
    if (Test-Path -LiteralPath $ledger) { $logLines = @(Get-Content -LiteralPath $ledger) }
    Check 'log-fix creates CHANGES.md with the ledger header' ($r.Code -eq 0 -and $logLines.Count -ge 3 -and $logLines[0] -eq '| Time | What | Command or setting | How to undo | Verified |' -and $logLines[1] -eq '|---|---|---|---|---|') $r.Out
    $cells = @()
    if ($logLines.Count -ge 3) { $cells = @(Read-Row $logLines[2]) }
    Check 'log-fix row keeps exactly five columns when the text has pipes' ($cells.Count -eq 5) ($logLines -join ';')
    Check 'log-fix keeps the What text exactly (double quotes, pipe, apostrophe, dollar)' ($cells.Count -eq 5 -and $cells[1] -ceq $what) ($cells -join ' || ')
    Check 'log-fix keeps the Command text exactly (double quotes and pipes)' ($cells.Count -eq 5 -and $cells[2] -ceq $cmdText) ($cells -join ' || ')
    Check 'log-fix keeps the Undo text exactly (double quotes and pipes)' ($cells.Count -eq 5 -and $cells[3] -ceq $undoText) ($cells -join ' || ')
    Check 'log-fix row ends Verified: no' ($cells.Count -eq 5 -and $cells[4] -eq 'no')
    Check 'log-fix stores a pipe as \| and never as /' ($logLines.Count -ge 3 -and $logLines[2].Contains('Out-Null') -and $logLines[2].Contains('\| Out-Null') -and -not $logLines[2].Contains('/ Out-Null'))
    $null = Invoke-LogFix @{ What = 'Second change'; Undo = 'Reverse it'; KitDir = $p2 }
    $logLines = @(Get-Content -LiteralPath $ledger)
    Check 'log-fix appends and does not overwrite' ($logLines.Count -eq 4 -and $logLines[2] -match 'Foo Helper' -and $logLines[3] -match 'Second change' -and $logLines[3] -match 'Reverse it')
    $r = Invoke-Script $lf @('-What', 'No undo given', '-KitDir', $p2)
    Check 'log-fix refuses a row with no undo' ($r.Code -ne 0 -and @(Get-Content -LiteralPath $ledger).Count -eq 4)
    $r = Invoke-Script $lf @('-What', 'Stray word', '-Undo', 'y', 'stray', '-KitDir', $p2)
    Check 'log-fix fails on a stray word (no positional binding)' ($r.Code -ne 0 -and @(Get-Content -LiteralPath $ledger).Count -eq 4) $r.Out
    $p2b = New-Kit 'logfix-nonewline'
    [IO.File]::WriteAllText((Join-Path $p2b 'CHANGES.md'), '| Time | What | Command or setting | How to undo | Verified |' + "`r`n" + '|---|---|---|---|---|')
    $null = Invoke-LogFix @{ What = 'After hand-made header'; Undo = 'z'; KitDir = $p2b }
    Check 'log-fix starts its row on a new line after a hand-made ledger' (@(Get-Content -LiteralPath (Join-Path $p2b 'CHANGES.md')).Count -eq 3)
    $r = Invoke-LogFix @{ What = 'x'; Undo = 'y'; KitDir = (Join-Path $root 'missing-dir') }
    Check 'log-fix fails loudly when the ledger cannot be written' ($r.Code -ne 0)

    # 3. safety.ps1. Checkpoint-Computer and Get-ComputerRestorePoint are stubbed as functions, so the REAL default
    #    path (admin check, post-Checkpoint existence check, existing-point path) is what runs. Nothing touches the PC.
    $safety = Join-Path $repo 'scripts\safety.ps1'
    $safetyText = [IO.File]::ReadAllText($safety)
    Check 'safety.ps1 has no RestorePointAction test hook' (-not $safetyText.Contains('RestorePointAction'))
    Check 'safety.ps1 calls reg.exe by its full path' ($safetyText.Contains('System32\reg.exe') -and $safetyText -notmatch '&\s+reg(\.exe)?\s')
    $global:CL = @{ Admin = $true; Calls = 0; Throw = $false; Persist = $true; Points = @(); Desc = '' }
    function global:Test-IsAdmin { $global:CL.Admin }
    function global:Enable-ComputerRestore { param($Drive) $global:CL.EnableCalls++ }
    function global:Checkpoint-Computer {
        [CmdletBinding()] param([string]$Description, [string]$RestorePointType)
        $global:CL.Calls++
        if ($global:CL.Throw) { throw 'stub: restore point refused' }
        $global:CL.Desc = $Description
        if ($global:CL.Persist) { $global:CL.Points = @($global:CL.Points) + (New-Point $Description 99 (Get-Date)) }
    }
    function global:Get-ComputerRestorePoint { $global:CL.Points }
    function global:New-Point {
        param([string]$Desc, [int]$Seq, [datetime]$When)
        [pscustomobject]@{ Description = $Desc; SequenceNumber = $Seq; CreationTime = [Management.ManagementDateTimeConverter]::ToDmtfDateTime($When) }
    }
    function Reset-Stubs { $global:CL = @{ Admin = $true; Calls = 0; Throw = $false; Persist = $true; Points = @(); Desc = ''; EnableCalls = 0 } }
    $stubsShadow = ((Get-Command Checkpoint-Computer).CommandType -eq 'Function' -and (Get-Command Get-ComputerRestorePoint).CommandType -eq 'Function')
    Check 'safety tests: the restore point stubs shadow the real commands' $stubsShadow
    function New-Run { [guid]::NewGuid().ToString() }
    function Read-Result { param([string]$Kit) $f = Join-Path $Kit 'backups\safety-result.txt'; if (Test-Path -LiteralPath $f) { [IO.File]::ReadAllText($f).Trim() } else { '' } }
    function Invoke-Safety {
        param([string]$Kit, [string]$Id, [hashtable]$Extra = @{})
        $o = & $safety -KitDir $Kit -RunId $Id @Extra *>&1 | Out-String
        [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
    }
    function Invoke-Hkcu { param([string]$Kit, [string]$Id) Invoke-Safety $Kit $Id @{ ExportHkcuOnly = $true } }

    if ($stubsShadow) {
        $kitBackups = Join-Path $repo 'backups'
        $kitBefore = Test-Path -LiteralPath $kitBackups

        # 3a. HKCU export step (runs in the assistant's own, non-elevated session).
        Reset-Stubs; $global:CL.Admin = $false
        $k = New-Kit 'safety-hkcu'; $id = New-Run
        $r = Invoke-Hkcu $k $id
        Check '-ExportHkcuOnly exits 0 without Administrator and makes no restore point' ($r.Code -eq 0 -and $global:CL.Calls -eq 0) $r.Out
        Check '-ExportHkcuOnly writes the run marker' (Test-Path -LiteralPath (Join-Path $k "backups\hkcu-done-$id.txt"))
        Check '-ExportHkcuOnly exports the HKCU Run key under the run id' ((-not (Test-Path 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Run')) -or (Test-Path -LiteralPath (Join-Path $k "backups\hkcu-run-$id.reg")))
        Check '-ExportHkcuOnly exports no machine-wide key and leaves no result file' (@(Get-ChildItem -LiteralPath (Join-Path $k 'backups') -Filter 'hklm-*' -ErrorAction SilentlyContinue).Count -eq 0 -and (Read-Result $k) -eq '')

        # 3b. Admin check on the default path.
        Reset-Stubs; $global:CL.Admin = $false
        $k = New-Kit 'safety-notadmin'; $id = New-Run
        $r = Invoke-Safety $k $id
        Check 'safety.ps1 stops with code 3 when not administrator and never calls Checkpoint-Computer' ($r.Code -eq 3 -and $global:CL.Calls -eq 0 -and $r.Out -match 'STOP:') $r.Out
        Check 'safety.ps1 records STOP code=3 with the RunId' ((Read-Result $k) -match "^STOP RunId=$id code=3 ")
        # The real admin check (no stub) must also say no in this non-elevated test session.
        $realAdmin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $realAdmin) {
            Remove-Item -Path 'Function:\Test-IsAdmin'
            Reset-Stubs
            $k = New-Kit 'safety-realcheck'; $id = New-Run
            $r = Invoke-Safety $k $id
            Check 'safety.ps1 real admin check refuses a non-elevated session' ($r.Code -eq 3 -and $global:CL.Calls -eq 0) $r.Out
            function global:Test-IsAdmin { $global:CL.Admin }
        }
        else { Write-Host 'INFO: test session is elevated; real admin-check refusal not exercised' }

        # 3c. Missing HKCU export for this run.
        Reset-Stubs
        $k = New-Kit 'safety-nohkcu'; $id = New-Run
        $r = Invoke-Safety $k $id
        Check 'safety.ps1 refuses (code 4) when this run''s HKCU export was not done first' ($r.Code -eq 4 -and $global:CL.Calls -eq 0 -and (Read-Result $k) -match "^STOP RunId=$id code=4") $r.Out

        # 3d. Bad or missing RunId.
        Reset-Stubs
        $k = New-Kit 'safety-badrun'
        $r = Invoke-Safety $k 'not-a-guid'
        Check 'safety.ps1 refuses a bad RunId' ($r.Code -eq 4 -and $global:CL.Calls -eq 0)
        $k = New-Kit 'safety-norun'
        $o = & $safety -KitDir $k *>&1 | Out-String
        Check 'safety.ps1 refuses a missing RunId' ($LASTEXITCODE -eq 4 -and $global:CL.Calls -eq 0 -and $o -match 'STOP:')

        # 3e. Default path, success: Checkpoint-Computer ran and the point exists afterwards.
        Reset-Stubs
        $k = New-Kit 'safety-ok'; $id = New-Run
        $null = Invoke-Hkcu $k $id
        $r = Invoke-Safety $k $id
        Check 'safety.ps1 default path exits 0 when the point is created and found' ($r.Code -eq 0 -and $global:CL.Calls -eq 1) $r.Out
        $res = Read-Result $k
        Check 'safety.ps1 success line is OK and carries the RunId' ($res -match "^OK RunId=$id restore point ") $res
        $bk = Join-Path $k 'backups'
        Check 'safety.ps1 wrote a baseline' (@(Get-ChildItem -LiteralPath $bk -Filter 'baseline-*.txt' -ErrorAction SilentlyContinue).Count -eq 1)
        Check 'safety.ps1 exported machine-wide keys' (@(Get-ChildItem -LiteralPath $bk -Filter 'hklm-run-*.reg' -ErrorAction SilentlyContinue).Count -eq 1)

        # 3f. Default path: Checkpoint-Computer "succeeds" (it only warns inside 24 hours) but no point exists.
        Reset-Stubs; $global:CL.Persist = $false
        $global:CL.Points = @(New-Point 'Earlier point' 7 (Get-Date).AddHours(-3))
        $k = New-Kit 'safety-silent'; $id = New-Run
        $null = Invoke-Hkcu $k $id
        $r = Invoke-Safety $k $id
        Check 'safety.ps1 stops with code 2 when Checkpoint-Computer made no point (a default that always reports success fails here)' ($r.Code -eq 2 -and $global:CL.Calls -eq 1 -and $r.Out -match 'STOP:') $r.Out
        $res = Read-Result $k
        Check 'safety.ps1 STOP line carries the RunId and code=2' ($res -match "^STOP RunId=$id code=2 ") $res
        Check 'safety.ps1 STOP lists the last 24 hours of restore points with dates' ($res -match 'Earlier point' -and $res -match '\d{4}-\d\d-\d\d \d\d:\d\d Earlier point') $res
        Check 'safety.ps1 makes no baseline or machine-wide export after a failed restore point' (@(Get-ChildItem -LiteralPath (Join-Path $k 'backups') -File | Where-Object { $_.Name -like 'baseline-*' -or $_.Name -like 'hklm-*' }).Count -eq 0)

        # 3g. Checkpoint-Computer throws; a stale OK from an older run must be overwritten.
        Reset-Stubs; $global:CL.Throw = $true
        $k = New-Kit 'safety-throw'; $id = New-Run
        $null = Invoke-Hkcu $k $id
        $old = New-Run
        Set-Content -LiteralPath (Join-Path $k 'backups\safety-result.txt') -Value "OK RunId=$old restore point 'old'; backups in x" -Encoding UTF8
        $r = Invoke-Safety $k $id
        $res = Read-Result $k
        Check 'safety.ps1 exits non-zero when the restore point throws' ($r.Code -eq 2 -and $r.Out -match 'STOP:' -and $r.Out -match 'restore point') $r.Out
        Check 'a stale OK from an older run is replaced by this run''s STOP' ($res -match "^STOP RunId=$id code=2" -and $res -notmatch '^OK') $res

        # 3h. Existing restore point path.
        Reset-Stubs
        $global:CL.Points = @(New-Point 'Made this morning' 3 (Get-Date).AddHours(-2))
        $k = New-Kit 'safety-existing'; $id = New-Run
        $null = Invoke-Hkcu $k $id
        $r = Invoke-Safety $k $id @{ UseExistingRestorePoint = $true }
        $res = Read-Result $k
        Check '-UseExistingRestorePoint accepts a point from the last 24 hours without creating one' ($r.Code -eq 0 -and $global:CL.Calls -eq 0 -and $res -match "^OK RunId=$id " -and $res -match 'existing') "$($r.Out) $res"
        Reset-Stubs
        $global:CL.Points = @(New-Point 'Too old' 2 (Get-Date).AddHours(-30))
        $k = New-Kit 'safety-existing-old'; $id = New-Run
        $null = Invoke-Hkcu $k $id
        $r = Invoke-Safety $k $id @{ UseExistingRestorePoint = $true }
        Check '-UseExistingRestorePoint refuses (code 2) when the newest point is older than 24 hours' ($r.Code -eq 2 -and $global:CL.Calls -eq 0 -and (Read-Result $k) -match "^STOP RunId=$id code=2") $r.Out

        # 3i. System Protection step uses the stub only when asked.
        Reset-Stubs
        $k = New-Kit 'safety-enable'; $id = New-Run
        $null = Invoke-Hkcu $k $id
        $r = Invoke-Safety $k $id @{ EnableSystemProtection = $true }
        Check '-EnableSystemProtection turns it on and then still makes and verifies the point' ($r.Code -eq 0 -and $global:CL.EnableCalls -eq 1 -and $global:CL.Calls -eq 1) $r.Out

        # 3j. An unexpected error ends in STOP, never left at RUNNING.
        Reset-Stubs
        $k = New-Kit 'safety-unexpected'; $id = New-Run
        $null = Invoke-Hkcu $k $id
        function global:Test-IsAdmin { throw 'stub: unexpected failure' }
        $r = Invoke-Safety $k $id
        function global:Test-IsAdmin { $global:CL.Admin }
        Check 'an unexpected error ends in a loud STOP and the result file is not left at RUNNING' ($r.Code -eq 4 -and (Read-Result $k) -match "^STOP RunId=$id code=4 Unexpected error") "$($r.Out) $(Read-Result $k)"

        # 3k. -WhatIf does nothing.
        Reset-Stubs
        $k = New-Kit 'safety-whatif'
        & $safety -KitDir $k -WhatIf *>&1 | Out-Null
        Check 'safety.ps1 -WhatIf exits 0 and creates nothing' ($LASTEXITCODE -eq 0 -and (Get-Tree $k).Count -eq 0 -and $global:CL.Calls -eq 0)
        Check 'safety.ps1 did not write into the real kit folder' ((Test-Path -LiteralPath $kitBackups) -eq $kitBefore)
    }
    Remove-Item -Path 'Function:\Test-IsAdmin', 'Function:\Checkpoint-Computer', 'Function:\Get-ComputerRestorePoint', 'Function:\Enable-ComputerRestore', 'Function:\New-Point' -ErrorAction SilentlyContinue

    # 4. Repository hygiene.
    $ps1Files = Get-ChildItem -LiteralPath $repo -Recurse -Filter '*.ps1' -File | Where-Object { $_.FullName -notmatch '\\\.git\\' }
    $nonAscii = @($ps1Files | Where-Object { [IO.File]::ReadAllBytes($_.FullName) | Where-Object { $_ -gt 127 } | Select-Object -First 1 })
    Check 'all .ps1 files are plain ASCII (PowerShell 5.1 safe)' ($nonAscii.Count -eq 0) (($nonAscii | ForEach-Object Name) -join ',')
    foreach ($n in 'fix-pc', 'change-ledger') {
        $sk = [IO.File]::ReadAllText((Join-Path $repo ".claude\skills\$n\SKILL.md"))
        Check "skill $n frontmatter has name and 'Use when'" ($sk -match "(?s)^---\r?\nname: $n\r?\ndescription: .*Use when.*?\r?\n---")
    }
    $fixpc = [IO.File]::ReadAllText((Join-Path $repo '.claude\skills\fix-pc\SKILL.md'))
    $ledgerSkill = [IO.File]::ReadAllText((Join-Path $repo '.claude\skills\change-ledger\SKILL.md'))
    $charter = [IO.File]::ReadAllText((Join-Path $repo 'CLAUDE.md'))
    $notice = [IO.File]::ReadAllText((Join-Path $repo 'NOTICE'))
    Check 'fix-pc runs collect.ps1 with process-scope bypass' ($fixpc.Contains('powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\collect.ps1'))
    Check 'fix-pc runs safety.ps1 and stops if it fails' ($fixpc.Contains('scripts\safety.ps1') -and $fixpc -match 'STOP')
    Check 'fix-pc quotes the safety.ps1 path and passes a new RunId' ($fixpc.Contains('"<kit folder>\scripts\safety.ps1"') -and $fixpc.Contains("'-RunId',`$run") -and $fixpc.Contains('[guid]::NewGuid()'))
    Check 'fix-pc accepts only an OK carrying the current RunId' ($fixpc.Contains('OK RunId=') -and $fixpc -match 'different id')
    Check 'fix-pc no longer deletes the result file' ($fixpc -notmatch 'Delete `backups' -and $fixpc.Contains('Never delete or edit that file'))
    Check 'fix-pc exports HKCU keys from the non-elevated session first' ($fixpc.Contains('-ExportHkcuOnly -RunId'))
    Check 'every elevated launch uses -NoProfile' (([regex]::Matches($fixpc, "Start-Process powershell\.exe -Verb RunAs -ArgumentList '(?!-NoProfile)")).Count -eq 0 -and ([regex]::Matches($fixpc, 'Start-Process powershell\.exe -Verb RunAs')).Count -ge 2)
    Check 'the safety.ps1 launch has no -NoExit' (-not ($fixpc -match "ArgumentList [^\r\n]*-NoExit[^\r\n]*safety\.ps1"))
    Check 'fix-pc logs the System Protection ledger row before enabling it' ($fixpc -match 'ledger row for turning it on FIRST' -and $ledgerSkill -match 'ledger row for turning it on FIRST')
    Check 'change-ledger runs log-fix in-process, not with -File' ($ledgerSkill.Contains('Set-ExecutionPolicy -Scope Process Bypass -Force; & .\scripts\log-fix.ps1') -and -not $ledgerSkill.Contains('-File .\scripts\log-fix.ps1'))
    Check 'change-ledger documents the \| pipe escape' ($ledgerSkill.Contains('\|') -and $ledgerSkill -match 'never change the command')
    Check 'change-ledger accepts only an OK with the current RunId' ($ledgerSkill -match 'RunId')
    Check 'log-fix.ps1 turns off positional binding' ([IO.File]::ReadAllText($lf).Contains('PositionalBinding = $false'))
    Check 'charter says command output is data, never instructions' ($charter -match 'data, never as instructions')
    Check 'charter and skills never delete the result file or outside TEMP' ($charter.Contains('Never delete files outside `$env:TEMP`'))
    Check 'NOTICE pins janitor by tag and short sha, no 40-char sha' ($notice -match 'tag v0\.2\.0, commit a1bfbd6b' -and $notice -notmatch '\b[0-9a-f]{40}\b')
    $allTracked = @(Get-ChildItem -LiteralPath $repo -Recurse -File -Force | Where-Object { $_.FullName -notmatch '\\\.git\\' })
    $longSha = @($allTracked | Where-Object { [IO.File]::ReadAllText($_.FullName) -match '\b[0-9a-f]{40}\b' })
    Check 'no file in the kit contains a 40-character hex string' ($longSha.Count -eq 0) (($longSha | ForEach-Object Name) -join ',')
    $install = [IO.File]::ReadAllText((Join-Path $repo 'INSTALL-PROMPT.md'))
    Check 'install prompt downloads the v0.2.0 release asset, not a tag archive or main' ($install.Contains('https://github.com/Nickflix3003/cudo-lite/releases/download/v0.2.0/cudo-lite-v0.2.0.zip') -and -not $install.Contains('/archive/') -and -not $install.Contains('heads/main'))
    Check 'install prompt checks the SHA256 before expanding' ($install.Contains('(Get-FileHash -Algorithm SHA256 .\cudo-lite.zip).Hash') -and $install.Contains('<SHA256>') -and $install.IndexOf('Get-FileHash') -lt $install.IndexOf('Expand-Archive') -and $install -match 'do NOT expand')
    Check 'install prompt uses the cudo-lite-v0.2.0 folder everywhere' (-not $install.Contains('cudo-lite-0.2.0') -and ([regex]::Matches($install, 'cudo-lite-v0\.2\.0')).Count -ge 5 -and $install.Contains('Remove-Item .\cudo-lite-v0.2.0 -Recurse -Force'))
    Check 'install prompt checks scripts\collect.ps1' ($install.Contains('scripts\collect.ps1'))

    # 5. The guarded temp cleanup block in fix-pc: refuses odd TEMP values and skips links.
    $m = [regex]::Match($fixpc, '(?s)Guarded temp cleanup.*?```\r?\n(.*?)```')
    Check 'fix-pc has a guarded temp cleanup block' $m.Success
    if ($m.Success) {
        $block = $m.Groups[1].Value -replace '\$delete = \$false', '$delete = $true'
        $blockFile = Join-Path (New-Kit 'tempblock') 'clean.ps1'
        Set-Content -LiteralPath $blockFile -Value $block -Encoding ASCII
        $fakeBase = New-Kit 'tempcase'
        $fake = Join-Path $fakeBase 'Temp'
        $keep = Join-Path $fakeBase 'keep'
        New-Item -ItemType Directory -Path (Join-Path $fake 'sub'), $keep | Out-Null
        Set-Content -LiteralPath (Join-Path $fake 'a.txt') -Value 'x'
        Set-Content -LiteralPath (Join-Path $fake 'sub\b.txt') -Value 'x'
        Set-Content -LiteralPath (Join-Path $keep 'canary.txt') -Value 'keep me'
        $link = Join-Path $fake 'link'
        & cmd.exe /c mklink /J "$link" "$keep" | Out-Null
        $savedTemp = $env:TEMP
        try {
            $env:TEMP = $fake
            $r = Invoke-Script $blockFile @()
            Check 'temp cleanup deletes files inside TEMP' ($r.Code -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $fake 'a.txt')) -and -not (Test-Path -LiteralPath (Join-Path $fake 'sub\b.txt'))) $r.Out
            Check 'temp cleanup skips a junction and never touches its target' ((Test-Path -LiteralPath (Join-Path $keep 'canary.txt')) -and $r.Out -match 'skipped link') $r.Out
            $env:TEMP = ''
            $r = Invoke-Script $blockFile @()
            Check 'temp cleanup refuses an empty TEMP' ($r.Code -ne 0 -and $r.Out -match 'Refusing') $r.Out
            $env:TEMP = (Join-Path $fakeBase 'does-not-exist')
            $r = Invoke-Script $blockFile @()
            Check 'temp cleanup refuses a TEMP folder that does not exist' ($r.Code -ne 0 -and $r.Out -match 'Refusing') $r.Out
            $env:TEMP = $env:USERPROFILE
            $r = Invoke-Script $blockFile @()
            Check 'temp cleanup refuses a TEMP that is the profile folder itself' ($r.Code -ne 0 -and $r.Out -match 'Refusing') $r.Out
            $env:TEMP = $keep
            $r = Invoke-Script $blockFile @()
            Check 'temp cleanup refuses a folder not named Temp' ($r.Code -ne 0 -and (Test-Path -LiteralPath (Join-Path $keep 'canary.txt'))) $r.Out
        }
        finally {
            $env:TEMP = $savedTemp
            & cmd.exe /c rmdir "$link" | Out-Null
        }
    }
}
catch {
    $script:fail++
    Write-Host "FAIL: test run aborted: $($_.Exception.Message) at $($_.InvocationInfo.ScriptLineNumber)"
}
finally {
    if ($root -and $root.StartsWith($env:TEMP) -and (Test-Path -LiteralPath $root)) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host "RESULT: $script:pass passed, $script:fail failed"
if ($script:fail -gt 0) { exit 1 }
exit 0

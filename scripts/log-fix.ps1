<#
.SYNOPSIS
  Appends one row to the kit's change ledger, CHANGES.md (the change-ledger skill's file).
.DESCRIPTION
  CHANGES.md lives in the kit folder (the parent of this scripts folder) and has the columns
  Time | What | Command or setting | How to undo | Verified. The row is added BEFORE the
  change runs, with Verified "no"; afterwards the assistant edits that row to "yes" or writes
  what went wrong. Fails loudly if the ledger cannot be written. A pipe in any text is stored
  as \| (read it back as a pipe); nothing else in the text is changed.
  Run it IN-PROCESS (Set-ExecutionPolicy -Scope Process Bypass -Force; & .\scripts\log-fix.ps1 ...),
  not with powershell -File, which mangles double quotes in arguments on Windows PowerShell 5.1.
  Stray words that are not named parameters are an error.
.EXAMPLE
  log-fix.ps1 -What "Disabled startup item Foo" -Command "Task Manager > Startup apps > Foo > Disable" -Undo "Task Manager > Startup apps > Foo > Enable"
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory = $true)][string]$What,
    [Parameter(Mandatory = $true)][string]$Undo,
    [string]$Command = 'n/a',
    [string]$Verified = 'no',
    [string]$KitDir = (Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference = 'Stop'
# A pipe would end the table cell, so it is stored as \| (the Markdown escape); the text is otherwise untouched.
function Format-Cell { param([string]$Text) ($Text -replace '\r?\n', ' ' -replace '\|', '\|').Trim() }
$log = Join-Path $KitDir 'CHANGES.md'
if (-not (Test-Path -LiteralPath $log)) {
    Set-Content -LiteralPath $log -Encoding UTF8 -Value @(
        '| Time | What | Command or setting | How to undo | Verified |',
        '|---|---|---|---|---|'
    )
}
$when = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$row = '| ' + (($when, (Format-Cell $What), (Format-Cell $Command), (Format-Cell $Undo), (Format-Cell $Verified)) -join ' | ') + ' |'
# A hand-made ledger may lack a final newline; start the row on its own line.
$existing = [IO.File]::ReadAllText($log)
if ($existing.Length -gt 0 -and -not $existing.EndsWith("`n")) { Add-Content -LiteralPath $log -Encoding UTF8 -Value '' }
Add-Content -LiteralPath $log -Encoding UTF8 -Value $row
Write-Host "Logged to $log"
Write-Host "UNDO: $Undo"

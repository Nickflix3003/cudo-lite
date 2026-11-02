# The welcome session runs this on a no. Removes only the two Cudo folders, and only if they are really Cudo's. Claude Code and the Claude app stay.
function Quoted([string]$p) { "'" + [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($p) + "'" }
$ErrorActionPreference = 'Stop'
$kit = $PSScriptRoot
$welcome = Join-Path $HOME 'cudo-welcome'
$targets = @()
$kept = ''
if (-not (Test-Path -LiteralPath (Join-Path $kit '.cudo-lite-kit'))) {
  $kept = " The folder $kit was kept because it is not marked as Cudo's."
} elseif ((Test-Path -LiteralPath (Join-Path $kit 'CHANGES.md')) -or (Test-Path -LiteralPath (Join-Path $kit 'backups'))) {
  $kept = " The folder $kit was kept because it holds the list of changes made to this PC and how to undo them."
} else { $targets += $kit }
$mark = Join-Path $welcome 'CLAUDE.md'
if ((Test-Path -LiteralPath $mark) -and ((Get-Content -LiteralPath $mark -TotalCount 1) -eq '# Cudo welcome')) { $targets += $welcome }
if (-not $targets) { "Cudo: nothing was removed.$kept"; exit 0 }
# Both folders can be in use while this runs (this script lives in one, and the session may sit in it), so a hidden helper
# in the temp folder keeps trying for an hour, then deletes itself. It runs from the temp folder so it holds neither one open.
$helper = Join-Path $env:TEMP ("cudo-remove-" + [guid]::NewGuid().ToString('N') + '.ps1')
@"
`$targets = @($(($targets | ForEach-Object { Quoted $_ }) -join ', '))
for (`$i = 0; `$i -lt 720; `$i++) {
  foreach (`$t in `$targets) { if (Test-Path -LiteralPath `$t) { Remove-Item -LiteralPath `$t -Recurse -Force -ErrorAction SilentlyContinue } }
  if (-not (`$targets | Where-Object { Test-Path -LiteralPath `$_ })) { break }
  Start-Sleep 5
}
Remove-Item -LiteralPath $(Quoted $helper) -ErrorAction SilentlyContinue
"@ | Set-Content -LiteralPath $helper -Encoding Unicode
Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$helper`"" -WorkingDirectory $env:TEMP -WindowStyle Hidden
"Cudo: removing the Cudo folders. Claude Code and the Claude app stay on this PC.$kept"

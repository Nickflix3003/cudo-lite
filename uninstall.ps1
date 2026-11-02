# The welcome session runs this on a no. Moves only the Cudo folders to the Recycle Bin, and only if they are really Cudo's, so a no can be undone. Claude Code and the Claude app stay.
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
if (-not $targets) { "Cudo: nothing was moved.$kept"; exit 0 }
# This script lives in the kit, so step out of it first.
Set-Location -LiteralPath $HOME
Add-Type -AssemblyName Microsoft.VisualBasic
$failed = @(); $moved = @()
foreach ($t in $targets) {
  try { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($t, [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin); $moved += $t }
  catch { $failed += $t }
}
$done = if ($moved) { " Sent to the Recycle Bin, if it is turned on on this PC: $($moved -join ', ')." } else { '' }
if ($failed) { "Cudo: these folders could not be moved, most likely because something has them open: $($failed -join ', ').$done$kept"; exit 1 }
"Cudo:$done Claude Code and the Claude app stay on this PC.$kept"

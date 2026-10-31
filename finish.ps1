# The welcome session runs this on a yes. It confirms the Cudo Lite kit is in place, which is all there is to finish today.
$missing = @('CLAUDE.md', 'scripts\collect.ps1', 'scripts\safety.ps1') | Where-Object { -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $_)) }
if ($missing) { "Cudo: something is missing from the install: $($missing -join ', ')"; exit 1 }
"Cudo: Cudo Lite is installed and ready, in $PSScriptRoot"

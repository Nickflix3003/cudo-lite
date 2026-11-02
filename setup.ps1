# Cudo setup, the one script the install prompt runs. Windows, no admin rights asked for by this script itself.
# 1. Finds a working Claude Code, or installs Anthropic's own.
# 2. Opens a new session page in the Claude desktop app with a message ready to send, with no terminal window and no second sign-in.
# It never skips or changes a Claude permission: the welcome session asks for approvals the normal way.
# Every line it prints starts with "Cudo:" so whoever runs it can repeat what happened in plain words.
$ErrorActionPreference = 'Stop'
$kit = $PSScriptRoot
$logFile = Join-Path $kit 'setup-log.txt'
function Say([string]$t) { "Cudo: $t"; "$(Get-Date -Format s) $t" | Add-Content -LiteralPath $logFile }
function Stop-Setup([string]$t, [int]$code) { Say "STOPPED: $t"; exit $code }

function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User') + ";$HOME\.local\bin"
}
function Find-Claude {
  # A leftover command can exist and not run, so each candidate has to answer before it counts.
  $tries = @(Get-Command claude -All -CommandType Application -ErrorAction SilentlyContinue | ForEach-Object Source) + "$HOME\.local\bin\claude.exe"
  foreach ($c in $tries) {
    if (-not $c -or -not (Test-Path -LiteralPath $c)) { continue }
    try { & $c --version *> $null; if ($LASTEXITCODE -eq 0) { return $c } } catch { }
  }
  return $null
}

Say 'starting'
$claude = Find-Claude
if (-not $claude) {
  Say 'Claude Code is not installed yet, installing it from Anthropic and accepting its installer agreements'
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    try { & winget install --id Anthropic.ClaudeCode --exact --silent --accept-package-agreements --accept-source-agreements *> $null } catch { }
    Refresh-Path
    $claude = Find-Claude
  }
  if (-not $claude) {
    # Anthropic's own installer, read into a file and run from there.
    $inst = Join-Path $env:TEMP ('claude-code-install-' + [guid]::NewGuid().ToString('N') + '.ps1')
    try {
      Invoke-WebRequest -UseBasicParsing -Uri 'https://claude.ai/install.ps1' -OutFile $inst
      & powershell -NoProfile -ExecutionPolicy Bypass -File $inst *> $null
    } catch { }
    Remove-Item -LiteralPath $inst -ErrorAction SilentlyContinue
    Refresh-Path
    $claude = Find-Claude
  }
  if (-not $claude) { Stop-Setup 'Claude Code could not be installed on this PC' 3 }
}
Say "Claude Code is ready"

# The app's sign-in does not carry over to terminal Claude, so nothing here starts a terminal session or asks for a second sign-in.
# It opens a new session page in the app, which already is signed in. The app fills the box and never sends it, so the person presses send.
if (-not (Test-Path -LiteralPath 'Registry::HKEY_CLASSES_ROOT\claude')) { Stop-Setup 'the Claude desktop app is not installed on this PC' 12 }
# The stick's scripts set CUDO_SOURCE, so the message says truthfully where the kit came from.
$ask = if ($env:CUDO_SOURCE -eq 'usb') { "Hello. I copied Cudo Lite from my USB stick into $kit. It is the kit from https://github.com/Nickflix3003/cudo-lite. Please read $kit\welcome\CLAUDE.md and follow it." }
else { "Hello. I downloaded Cudo Lite from https://github.com/Nickflix3003/cudo-lite into $kit. Please read $kit\welcome\CLAUDE.md and follow it." }
try { Start-Process ('claude://code/new?q=' + [uri]::EscapeDataString($ask)) }
catch { Stop-Setup "the Claude app could not be opened: $_" 13 }
Say 'DONE: a new session page is open in the Claude app with a message ready. Go there and press send'

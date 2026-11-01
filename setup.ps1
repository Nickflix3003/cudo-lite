# Cudo setup, the one script the install prompt runs. Windows, no admin rights asked for by this script itself.
# 1. Finds a working Claude Code, or installs Anthropic's own.  2. Makes the Cudo welcome folder.
# 3. Opens a welcome session in the Claude desktop app, with no terminal window. If terminal Claude is not signed in, it opens a new
#    session page in the app instead, with a message ready to send, and never asks for a second sign-in.
# It never skips or changes a Claude permission: the welcome session asks for approvals the normal way.
# Every line it prints starts with "Cudo:" so whoever runs it can repeat what happened in plain words.
$ErrorActionPreference = 'Stop'
$kit = $PSScriptRoot
$welcome = Join-Path $HOME 'cudo-welcome'
$logFile = Join-Path $kit 'setup-log.txt'
function Say([string]$t) { "Cudo: $t"; "$(Get-Date -Format s) $t" | Add-Content -LiteralPath $logFile }
$createdWelcome = $false
function Stop-Setup([string]$t, [int]$code) {
  # A failed run leaves nothing of its own behind, so running setup again starts clean.
  if ($createdWelcome) { Set-Location -LiteralPath $kit; Remove-Item -LiteralPath $welcome -Recurse -Force -ErrorAction SilentlyContinue }
  Say "STOPPED: $t"; exit $code
}

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

# A folder from an earlier run of this setup is reused, so running it again works. Anything else with this name is left alone.
$mark = Join-Path $welcome 'CLAUDE.md'
if (Test-Path -LiteralPath $welcome) {
  if (-not ((Test-Path -LiteralPath $mark) -and ((Get-Content -LiteralPath $mark -TotalCount 1) -eq '# Cudo welcome'))) {
    Stop-Setup "the folder $welcome already exists and is not Cudo's, so nothing was changed" 4
  }
} else {
  New-Item -ItemType Directory $welcome | Out-Null
  $createdWelcome = $true
}
try {
  Copy-Item -LiteralPath (Join-Path $kit 'welcome\CLAUDE.md') -Destination (Join-Path $welcome 'CLAUDE.md')
  Set-Location -LiteralPath $welcome
} catch { Stop-Setup "the welcome folder could not be set up: $_" 10 }

# Setup runs inside a Claude session; a session marked as its child saves no transcript, and the app could not open it.
Remove-Item Env:CLAUDE_CODE_CHILD_SESSION -ErrorAction SilentlyContinue

function Start-Welcome {
  # No tools and one turn: this session can only say hello, and it ends right after.
  $errFile = Join-Path $kit 'welcome-errors.txt'
  # Claude writes warnings to its error stream, which must not end this script; the '""' keeps an empty value on Windows PowerShell 5.1.
  $ErrorActionPreference = 'Continue'
  $raw = $null | & $claude -p 'hello' --output-format json --tools '""' --max-budget-usd 0.5 2> $errFile | Out-String
  $ErrorActionPreference = 'Stop'
  try { return ($raw | ConvertFrom-Json) } catch { return $null }
}

function Open-WelcomeInApp {
  # Terminal Claude could not start, most often because it has no sign-in: the app's does not carry over to it. So instead of asking this
  # person to sign in a second time, open a new session page in the app, which already is signed in. The app fills the box and never sends it, so they press send.
  if (-not (Test-Path -LiteralPath 'Registry::HKEY_CLASSES_ROOT\claude')) { Stop-Setup 'the Claude desktop app is not installed on this PC' 12 }
  $ask = "Hello. Please read $welcome\CLAUDE.md and follow it."
  try { Start-Process ('claude://code/new?q=' + [uri]::EscapeDataString($ask)) }
  catch { Stop-Setup "the Claude app could not be opened: $_" 13 }
  Say 'DONE: a new session page is open in the Claude app with a message ready. Go there and press send'
  exit 0
}

$w = Start-Welcome
if (-not $w -or $w.is_error -or -not $w.session_id) { Open-WelcomeInApp }
Say 'the welcome session is ready'

# --desktop refuses redirected output, so it gets its own hidden console and no terminal shows.
try { $p = Start-Process $claude -ArgumentList '--desktop', '--resume', $w.session_id -WorkingDirectory $welcome -WindowStyle Hidden -PassThru }
catch { Stop-Setup "the Claude app could not be opened: $_" 11 }
if (-not $p.WaitForExit(60000)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; Stop-Setup 'the Claude app did not open the session within a minute' 7 }
if ($p.ExitCode -ne 0) { Stop-Setup "the Claude app could not open the session (code $($p.ExitCode))" 8 }
Say 'DONE: a new session in the cudo-welcome folder is open in the Claude app. Go there and answer its question'

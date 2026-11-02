# Cudo Lite

Cudo Lite is a safety charter, two skills and three small PowerShell scripts that let Claude Code diagnose and fix problems on a Windows PC, with the owner's permission at every step.

- **Nothing keeps running.** No services, no scheduled tasks, no startup entries. Setup runs nothing in the background. If you answer no, the Cudo folders go to the Recycle Bin.
- **Nothing phones home.** No telemetry, no uploads, no accounts of its own. The one flow of data is Claude itself: what the assistant reads is sent to the Claude account you are signed in to. Setup never asks you to sign in.
- **Nothing changes without a typed yes.** The assistant looks first (read-only), then asks before each change.

## What is in the box

- `CLAUDE.md`: the charter. Claude Code reads it when you open this folder.
- `.claude/skills/fix-pc`: runs the read-only diagnosis, ranks the causes, and lists repairs that each need a restore point and a yes.
- `.claude/skills/change-ledger`: records every change in `CHANGES.md` with its undo.
- `scripts/`: `collect.ps1` is a read-only health report (saved to `reports/` in this folder); `safety.ps1` makes the System Restore point and saves a backup of the startup settings and a baseline into `backups/` (it runs only after your yes, in an Administrator window); `log-fix.ps1` adds a row to `CHANGES.md`. They run for this session only, from this folder; nothing is installed and nothing is written outside this folder except the restore point Windows itself keeps.
- `setup.ps1`, `finish.ps1`, `uninstall.ps1`, `welcome/`: the one-prompt install, described below.
- `tests/test_cudo_lite.ps1`: checks for the scripts (the restore point is stubbed in the tests, never made).
- `NOTICE`, `LICENSE`: MIT, with the notice for the project some ideas were adapted from.

## Install

Open the Claude desktop app, go to the Code tab, and paste the prompt from `INSTALL-PROMPT.md`. It downloads this kit into a `cudo-lite` folder in your home folder, checks it, and runs `setup.ps1`.

`setup.ps1` finds Claude Code, or installs Anthropic's own if it is missing (accepting the installer's agreements for you, which the prompt says up front), then opens a new session page in the app, with a message ready. You press send, and that session asks whether to finish installing. You never sign in twice.

## Remove

Answer no in the welcome session, or delete the `cudo-lite` folder. Answering no moves `cudo-lite` to the Recycle Bin, and a `cudo-welcome` folder if an older version made one, unless Cudo has already made changes on this PC, in which case `cudo-lite` stays so you keep the list of changes. Claude Code stays either way.

Every change the assistant made to the PC is listed in `CHANGES.md` with the way to undo it, so you can reverse any of them first. System restore points it created stay in Windows until you remove them in System Protection settings.

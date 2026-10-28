# Cudo Lite

Cudo Lite is a safety charter, two skills and three small PowerShell scripts that let Claude Code diagnose and fix problems on a Windows PC, with the owner's permission at every step.

- **Nothing runs in the background.** No services, no scheduled tasks, no startup entries.
- **Nothing phones home.** No telemetry, no uploads, no accounts, no sign-ins. The one flow of data is Claude itself: what the assistant reads from the report is sent to the Claude account you are signed in to.
- **Nothing changes without a typed yes.** The assistant looks first (read-only), then asks before each change.

## What is in the box

- `CLAUDE.md`: the charter. Claude Code reads it when you open this folder.
- `.claude/skills/fix-pc`: runs the read-only diagnosis, ranks the causes, and lists repairs that each need a restore point and a yes.
- `.claude/skills/change-ledger`: records every change in `CHANGES.md` with its undo.
- `scripts/`: `collect.ps1` is a read-only health report (saved to `reports/` in this folder); `safety.ps1` makes the System Restore point and saves a backup of the startup settings and a baseline into `backups/` (it runs only after your yes, in an Administrator window); `log-fix.ps1` adds a row to `CHANGES.md`. They run for this session only, from this folder; nothing is installed and nothing is written outside this folder except the restore point Windows itself keeps.
- `tests/test_cudo_lite.ps1`: checks for the scripts (the restore point is stubbed in the tests, never made).
- `NOTICE`, `LICENSE`: MIT, with the notice for the project some ideas were adapted from.

## Install

Open the Claude desktop app, go to the Code tab, pick an empty folder, and paste the prompt from `INSTALL-PROMPT.md`.

## Remove

Delete the folder. Every change the assistant made to the PC is listed in `CHANGES.md` with the way to undo it, so you can reverse any of them first. System restore points it created stay in Windows until you remove them in System Protection settings.

# Cudo Lite

Cudo Lite is a safety charter plus two skills that let Claude Code diagnose and fix problems on a Windows PC, with the owner's permission at every step.

- **Nothing runs in the background.** No services, no scheduled tasks, no startup entries.
- **Nothing phones home.** No telemetry, no uploads, no accounts, no sign-ins.
- **Nothing changes without a typed yes.** The assistant looks first (read-only), then asks before each change.

## What is in the box

- `CLAUDE.md`: the charter. Claude Code reads it when you open this folder.
- `.claude/skills/fix-pc`: a read-only diagnosis runbook, plus a list of repairs that each need a restore point and a yes.
- `.claude/skills/change-ledger`: records every change in `CHANGES.md` with its undo.

## Install

Open the Claude desktop app, go to the Code tab, pick an empty folder, and paste the prompt from `INSTALL-PROMPT.md`.

## Remove

Delete the folder. Every change the assistant made to the PC is listed in `CHANGES.md` with the way to undo it, so you can reverse any of them first. System restore points it created stay in Windows until you remove them in System Protection settings.

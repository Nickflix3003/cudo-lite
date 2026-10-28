---
name: change-ledger
description: Records every change made to this PC in CHANGES.md with its undo, and creates the restore point first. Use when the assistant is about to make a change, or the owner says "record the change", "what did you change", "undo", "roll that back", or "restore".
---

# /change-ledger: nothing changes without a row and a restore point

Keep `CHANGES.md` in the working folder (the folder this kit lives in). Create it if it is missing, with this header:

```
| Time | What | Command or setting | How to undo | Verified |
|---|---|---|---|---|
```

## Before every change

1. **State the change and its undo**, one line each, say a restore point will be made first, and wait for the owner's typed "yes". No yes means no restore point and no change.
2. **Restore point, once per session.** This session is not running as Administrator, so `scripts\safety.ps1` runs in its own Administrator window, as the `fix-pc` skill describes under "Restore point and safety net". It makes the restore point, exports the startup keys and writes a baseline into `backups\` in this folder, and reports `OK` or `STOP` in `backups\safety-result.txt`, and only an `OK` that carries this run's own RunId counts. **A STOP, or no OK, ends the run: make no change and tell the owner plainly.** Windows allows one restore point per 24 hours; a restore point made earlier in this session covers later changes, so do not make a second one. If one already exists from today, give the owner its date and ask before accepting it. Do not change the setting that limits restore points. If System Protection is off, tell the owner and ask; with a yes, add the ledger row for turning it on FIRST (step 3 below), then run the script again with `-EnableSystemProtection`.
3. **Append the row BEFORE running the change.** Time, what, the exact command or setting, how to undo, and `Verified: no`. Use the script, so the row is always well formed and the ledger stays in this one place:
   `Set-ExecutionPolicy -Scope Process Bypass -Force; & .\scripts\log-fix.ps1 -What '<what>' -Command '<exact command or setting>' -Undo '<how to undo>'`
   Run it in this session's own PowerShell, not with `powershell -File`: an argument passed through `-File` loses its double quotes on Windows PowerShell 5.1. Inside single quotes, double any apostrophe in the text (Microsoft''s). Every parameter is named; a stray word is an error.
   The script keeps the text exactly as given, except that a pipe is written `\|` so the table stays five columns (read `\|` back as a pipe). If you edit a row by hand, keep that escape and never change the command itself.
   If it fails, the ledger was not written: stop and tell the owner.
4. **Run the change**, then check it worked (re-run the read-only check that showed the problem).
5. **Update the row** in `CHANGES.md` to `Verified: yes`, or write what went wrong. A failed change is still a row.

## When the owner says "undo"

1. Read `CHANGES.md` and tell the owner which row you are about to reverse (the most recent one that is not already undone).
2. Wait for a typed yes.
3. Run the undo from that row, verify, and add a new row saying the change was reversed.
4. If the row says it cannot be undone, say so, and offer the restore point instead (`rstrui.exe` opens System Restore; the owner picks the point and confirms it).

## When the owner asks "what did you change"

Print the ledger in plain English, newest first, one sentence per row.

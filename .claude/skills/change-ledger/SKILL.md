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

1. **Restore point.** Run in PowerShell:
   `Checkpoint-Computer -Description "cudo-lite before <change>" -RestorePointType MODIFY_SETTINGS`
   Windows allows one restore point per 24 hours by default. If it refuses, say so plainly and ask the owner whether to proceed without a new one. Do not change the setting that limits restore points. If System Protection is off, tell the owner and ask; do not turn it on without a yes.
2. **State the change and its undo**, one line each, and wait for the owner's typed "yes".
3. **Append the row BEFORE running the change.** Time, what, the exact command or setting, how to undo, and `Verified: no`.
4. **Run the change**, then check it worked (re-run the read-only check that showed the problem).
5. **Update the row** to `Verified: yes`, or write what went wrong. A failed change is still a row.

## When the owner says "undo"

1. Read `CHANGES.md` and tell the owner which row you are about to reverse (the most recent one that is not already undone).
2. Wait for a typed yes.
3. Run the undo from that row, verify, and add a new row saying the change was reversed.
4. If the row says it cannot be undone, say so, and offer the restore point instead (`rstrui.exe` opens System Restore; the owner picks the point and confirms it).

## When the owner asks "what did you change"

Print the ledger in plain English, newest first, one sentence per row.

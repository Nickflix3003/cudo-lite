# Install prompt

Open the Claude desktop app, go to the Code tab, choose an empty folder, and paste everything inside the box below.

```
You are in an empty folder on a Windows PC. Install "Cudo Lite" here, using PowerShell for every command:

1. Run: Invoke-WebRequest -Uri https://github.com/Nickflix3003/cudo-lite/archive/refs/heads/main.zip -OutFile cudo-lite.zip
2. Run: Expand-Archive cudo-lite.zip -DestinationPath . -Force
3. Move everything inside the extracted cudo-lite-main folder up into the current folder, including the hidden .claude folder (use Get-ChildItem -Force and Move-Item).
4. Delete cudo-lite.zip and the now-empty cudo-lite-main folder. Delete nothing else.
5. Read CLAUDE.md and the two skills under .claude/skills (fix-pc and change-ledger). Follow CLAUDE.md for the rest of this session.
6. Confirm in one line what was installed and that you will ask before making any change.
7. Then start the fix-pc skill by asking me what has been going wrong, since when, and what changed recently. Do not run anything else until I answer.
```

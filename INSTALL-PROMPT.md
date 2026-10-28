# Install prompt

Open the Claude desktop app, go to the Code tab, choose an empty folder, and paste everything inside the box below.

```
You are in an empty folder on a Windows PC. Install "Cudo Lite" here, using PowerShell for every command:

1. Run: Get-ChildItem -Force. If anything is here other than a .claude folder, stop and ask me to pick an empty folder.
2. Run: Invoke-WebRequest -Uri https://github.com/Nickflix3003/cudo-lite/archive/refs/heads/main.zip -OutFile cudo-lite.zip -UseBasicParsing
3. Run: Expand-Archive cudo-lite.zip -DestinationPath . -Force
4. Run: Copy-Item -Path .\cudo-lite-main\* -Destination . -Recurse -Force
   Then run: Copy-Item -Path .\cudo-lite-main\.claude -Destination . -Recurse -Force
5. Check that .\CLAUDE.md, .\.claude\skills\fix-pc\SKILL.md and .\.claude\skills\change-ledger\SKILL.md exist. If any is missing, stop and tell me.
6. Run: Remove-Item .\cudo-lite.zip; Remove-Item .\cudo-lite-main -Recurse -Force. Delete nothing else.
7. Read CLAUDE.md and the two skills under .claude/skills (fix-pc and change-ledger). Follow CLAUDE.md for the rest of this session.
8. Confirm in one line what was installed and that you will ask before making any change.
9. Then start the fix-pc skill by asking me what has been going wrong, since when, and what changed recently. Do not run anything else until I answer.
```

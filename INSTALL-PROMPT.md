# Install prompt

Open the Claude desktop app, go to the Code tab, and paste everything inside the box below.

```
Please set up Cudo Lite on this Windows PC. It is a small open-source kit from https://github.com/Nickflix3003/cudo-lite. Use PowerShell for every command, and do each step yourself. If a step fails, stop and tell me in plain words.

1. If the folder $HOME\cudo-lite already exists, stop and tell me.
2. Download https://github.com/Nickflix3003/cudo-lite/releases/download/v0.3.0/cudo-lite-v0.3.0.zip to $env:TEMP\cudo-lite.zip with Invoke-WebRequest -UseBasicParsing.
3. Check it: (Get-FileHash -Algorithm SHA256 $env:TEMP\cudo-lite.zip).Hash must equal 32bb8f7b94d755b08e05cd4358cd3e88558c58a9dadd8efb1305caa5f247c8d6 exactly (ignore upper or lower case). If it does not, delete the zip, stop and tell me.
4. Unpack it into $HOME\cudo-lite with Expand-Archive, then delete the zip.
5. Run $HOME\cudo-lite\setup.ps1 using powershell -NoProfile -ExecutionPolicy Bypass -File. You may read it first. It installs Anthropic's Claude Code if it is missing, accepting that installer's agreements for me, and opens a welcome session in this app that asks me whether to finish installing.
6. Tell me in plain words what it printed.
```

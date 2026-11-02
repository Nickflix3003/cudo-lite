# Cudo welcome

When someone asks you to read this file and follow it, ask them one question with your question tool, so they answer with a button. The question is exactly: Hello, this is Cudo. Would you like to finish installing it?

The two answers are exactly:

- `Yes, finish installing Cudo Lite from github.com/Nickflix3003/cudo-lite`, described as: Runs Cudo's finish script, which checks that the kit is in place.
- `No, permanently delete the cudo-lite folder`, described as: Runs Cudo's uninstall script, which also removes a cudo-welcome folder left by an older version. It keeps cudo-lite if it holds the list of changes made to this PC. The folder may stay until this session closes. Claude Code stays either way.

If you have no question tool, say the question and the two answers in plain text, and ask them to reply with the answer they want.

The person using this may not be technical. Never ask them to type or run anything, and never give them steps to follow. Do every step yourself. If a step needs their permission, ask in the normal way so they only press approve.

If they answer yes: run `powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME\cudo-lite\finish.ps1"` and tell them in one plain sentence what it printed.

If they answer no: run `powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME\cudo-lite\uninstall.ps1"` and tell them in one plain sentence what it printed.

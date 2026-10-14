# claude-code-windows-toast

**English** | [简体中文](README.zh-CN.md)

Native Windows toast notifications for **Claude Code** — know the moment a task finishes, fails, or needs your attention.

Works with both the **Claude Code CLI** and the **VS Code extension** (they share the same `~/.claude/settings.json`). Zero dependencies: it only uses the built-in Windows PowerShell 5.1 and the native WinRT toast API.

> Unofficial community project. Not affiliated with Anthropic.

## What you get

| When | Notification |
| --- | --- |
| Task finished | `[project] Task complete` + a short preview of the final reply |
| A turn fails with an API error (connection problems, rate limits, auth failures, server errors, ...) | `[project] Task error - reason` + a short error preview |
| A multiple-choice question (`AskUserQuestion`) or plan approval (`ExitPlanMode`) is about to appear | `[project] Waiting for your choice` |
| A permission prompt is about to appear (`PermissionRequest`) | `[project] Waiting for approval: tool` |
| An MCP elicitation form is about to appear (`Elicitation`) | `[project] Waiting for input (server)` |
| Background sessions finish or need input; quota auto-resume notices | `[project] ...` (fires in the relevant scenarios) |

- **Native** — Windows toast API; no modules, no background service, no third-party components.
- **Safe** — the hook never writes to stdout and always exits 0, so it can never allow or block a tool call by accident.
- **Reliable** — failure notifications are handed to a detached helper process, so they still arrive when Claude Code exits immediately after an error (for example `claude -p`, or connection failures after retries).

## Requirements

- Windows 10 / 11
- Claude Code (CLI and/or the VS Code extension) — tested with v2.1.296 - v2.1.299
- Windows PowerShell 5.1 (preinstalled on Windows)

## Files

| File | Purpose |
| --- | --- |
| `claude-notify.ps1` | The notification script (reads the hook event, shows the toast) |
| `stopfailure-launcher.cmd` | Tiny launcher for the failure hook (detached delivery; uses `%~dp0`, no machine-specific paths) |
| `install-claude-notify.ps1` | One-shot installer (copies both scripts, merges six hook events, backs up settings, upgrades v1 in place) |
| `settings-hooks-snippet.json` | Manual configuration snippet (replace `<USER>` with your user name) |

## Installation

### Option A — installer script (recommended)

1. Download this repository (**Code → Download ZIP**) or the package from Releases.
2. Open PowerShell in the extracted folder and run:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-claude-notify.ps1
   ```

3. Start a new Claude Code session (CLI or VS Code panel). Done.

The installer copies the scripts to `%USERPROFILE%\.claude\hooks\`, merges the hook configuration into `%USERPROFILE%\.claude\settings.json`, and creates a timestamped backup first. It is idempotent, and running it on a v1 installation upgrades it in place.

### Option B — manual setup

1. Copy `claude-notify.ps1` **and** `stopfailure-launcher.cmd` to `C:\Users\<you>\.claude\hooks\` (create the folder if needed).
2. Merge `settings-hooks-snippet.json` into `C:\Users\<you>\.claude\settings.json`, replacing `<USER>` with your user name. The two script files themselves need no edits — the launcher resolves the script sitting next to it.

## Verifying it works

- Send any prompt; when the reply finishes you should get a "Task complete" toast.
- Trigger a question box or a permission dialog; you should get a "Waiting ..." toast right away.
- For troubleshooting, see `%LOCALAPPDATA%\claude-notify\debug.log` (written by the hook) and `claude --debug hooks`.

## Troubleshooting

- **No notification at all** — check *Settings → System → Notifications*: "Windows PowerShell" must be enabled, and Focus Assist must be off.
- **"File is blocked" after download** — right-click the file → Properties → check *Unblock*.
- **Garbled text in the toast** — make sure the script kept its UTF-8 (with BOM) encoding.

## Upgrade from v1

Run the same installer command again. Existing entries are replaced in place (matcher updates included) and your other hooks are left untouched.

## Uninstall

1. Remove the six hook entries from `settings.json` (or the whole `hooks` key if it holds no other hooks).
2. Delete `%USERPROFILE%\.claude\hooks\claude-notify.ps1` and `stopfailure-launcher.cmd`.

## How it works

```
Claude Code hook event
  |- Stop / PreToolUse / PermissionRequest / Elicitation / Notification
  |     -> powershell.exe -File claude-notify.ps1   (reads JSON, shows toast)
  |- StopFailure
        -> cmd launcher -> detached helper process -> toast
```

Hook events used: `Stop`, `PreToolUse` (AskUserQuestion / ExitPlanMode), `PermissionRequest`, `StopFailure`, `Elicitation`, `Notification` (permission prompts, background sessions, quota notices).

## Limitations

- Windows only.
- Notifications appear under the name "Windows PowerShell" (borrowed system AUMID).
- User interrupts (Esc) and process crashes cannot notify — Claude Code provides no hook events for them.
- One notification per finished turn; multiple windows/sessions produce multiple notifications.

## License

[MIT](LICENSE)
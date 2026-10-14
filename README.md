# claude-code-windows-toast

**English** | [简体中文](README.zh-CN.md)

Native Windows toast notifications for **Claude Code** — get a bottom-right notification when a task completes, when Claude is waiting for your choice, or when a permission prompt needs your approval.

Works with both the **Claude Code CLI** and the **VS Code extension** (they share the same `~/.claude/settings.json`). Zero dependencies: it only uses the built-in Windows PowerShell 5.1 and the native WinRT toast API.

> Unofficial community project. Not affiliated with Anthropic.

## What you get

| Trigger | Notification |
| --- | --- |
| Task finished | `[project] Task complete` + a short preview of the final reply |
| A multiple-choice question (`AskUserQuestion`) or plan approval (`ExitPlanMode`) is about to appear | `[project] Waiting for your choice` |
| A permission prompt is about to appear (`PermissionRequest`) | `[project] Waiting for approval: <tool>` |
| MCP elicitation form / URL request | `[project] Needs your attention` (after ~6 s) |

- **Native** — uses the Windows toast API; no modules, no background service, no third-party components.
- **Safe** — the hook script never writes to stdout and always exits 0, so it can never allow or block a tool call by accident.
- **Lightweight** — adds about 0.5 s at the end of a turn (can be made fully asynchronous).

## Requirements

- Windows 10 / 11
- Claude Code (CLI and/or the VS Code extension) — tested with v2.1.296
- Windows PowerShell 5.1 (preinstalled on Windows)

## Installation

### Option A — installer script (recommended)

1. Download this repository (**Code → Download ZIP**) or a release package.
2. Open PowerShell in the extracted folder and run:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-claude-notify.ps1
   ```

3. Start a new Claude Code session (CLI or VS Code panel). Done.

The installer copies `claude-notify.ps1` to `%USERPROFILE%\.claude\hooks\`, merges the hook configuration into `%USERPROFILE%\.claude\settings.json`, and creates a timestamped backup of the settings file first. Running it again does not create duplicates.

### Option B — manual setup

1. Copy `claude-notify.ps1` to `C:\Users\<you>\.claude\hooks\` (create the folder if needed).
2. Merge `settings-hooks-snippet.json` into `C:\Users\<you>\.claude\settings.json`, replacing `<USER>` in the script path with your actual user name.

## Verifying it works

- Send any prompt; when the reply finishes you should get a "Task complete" toast.
- Trigger a question box or a permission dialog; you should get a "Waiting ..." toast right away.
- Inspect the hooks engine with `claude --debug hooks`.

## Troubleshooting

- **No notification at all** — check *Settings → System → Notifications*: "Windows PowerShell" must be enabled, and Focus Assist must be off.
- **"File is blocked" after download** — right-click the file → Properties → check *Unblock*.
- **Garbled text in the toast** — make sure the script kept its UTF-8 (with BOM) encoding.

## Customization

- Message strings live in `claude-notify.ps1`.
- Want the popup instantly and the toast about 0.5 s later? Add `"async": true` to the hook entries in `settings.json`.
- Want the toast to show as **Claude Code** instead of "Windows PowerShell"? That requires registering a custom AUMID (a possible future enhancement).

## Uninstall

1. Remove the four hook entries from `settings.json` (or the whole `hooks` key if it holds no other hooks).
2. Delete `%USERPROFILE%\.claude\hooks\claude-notify.ps1`.

## How it works

```
Claude Code event ──▶ hook command (powershell.exe -File claude-notify.ps1)
                        │  reads the event JSON from stdin
                        └─▶ WinRT ToastNotificationManager.Show()
```

Hook events used:

| Event | Purpose |
| --- | --- |
| `Stop` | Main agent finished a response |
| `PreToolUse` (`AskUserQuestion\|ExitPlanMode`) | Question / plan-approval box is about to appear |
| `PermissionRequest` | Permission dialog is about to appear |
| `Notification` (`elicitation_dialog\|elicitation_url_dialog`) | MCP elicitation dialogs |

## Limitations

- Windows only.
- Notifications appear under the name "Windows PowerShell" (borrowed system AUMID).
- One notification per finished turn; multiple windows/sessions produce multiple notifications.
- `Esc` interrupts do not fire `Stop` (Claude Code behaviour).
- Sandboxed network-request prompts are not covered yet (one extra matcher would add it).

## License

[MIT](LICENSE)
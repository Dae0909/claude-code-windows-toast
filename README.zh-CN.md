# claude-code-windows-toast

[English](README.md) | **简体中文**

给 **Claude Code** 加上 Windows 原生 Toast 通知 —— 任务完成、任务出错、需要你选择 / 批准时，右下角自动提醒。

支持 **Claude Code CLI** 和 **VS Code 插件**（两者共享同一份 `~/.claude/settings.json`）。零依赖：只用 Windows 自带的 PowerShell 5.1 和系统原生 WinRT Toast API。

> 社区非官方项目，与 Anthropic 无关。

## 覆盖的场景

| 时机 | 通知内容 |
| --- | --- |
| 任务完成 | `[项目名] 任务完成` + 最后回复摘要 |
| 任务因 API 错误失败（连接失败、限额、认证失败、服务端错误等） | `[项目名] 任务出错 · 原因` + 错误摘要 |
| 弹出选择题框 / 计划确认框 | `[项目名] 在等你选择` |
| 即将弹出权限批准框 | `[项目名] 在等你批准：工具名` |
| 即将弹出 MCP 表单 | `[项目名] 在等你填写表单（服务器）` |
| 后台会话结束 / 等输入、限额自动恢复 | `[项目名] ...`（对应场景出现时） |

- **原生**：Windows 通知 API，无第三方模块、无后台服务；
- **安全**：hook 从不向 stdout 输出、始终 exit 0，绝不会误允许 / 误拦截任何操作；
- **可靠**：失败类通知通过"分离进程"投递，即使 Claude Code 在报错后立即退出（例如 `claude -p`、连接失败重试耗尽后退出）也能弹出来。

## 环境要求

- Windows 10 / 11
- Claude Code（CLI 或 VS Code 插件，任一即可）—— 实测 v2.1.296 - v2.1.299
- Windows PowerShell 5.1（系统自带）

## 文件说明

| 文件 | 用途 |
| --- | --- |
| `claude-notify.ps1` | 通知脚本（读取 hook 事件并弹窗） |
| `stopfailure-launcher.cmd` | 失败事件专用启动器（分离进程投递；用 `%~dp0` 定位，无需修改路径） |
| `install-claude-notify.ps1` | 一键安装（复制两个脚本 + 合并 6 个事件 + 自动备份 + 原地升级 v1） |
| `settings-hooks-snippet.json` | 手动配置片段（把 `<USER>` 换成你的用户名） |

## 安装

### 方式 A：一键安装（推荐）

1. 下载本仓库（**Code → Download ZIP**）或 Releases 里的安装包；
2. 在解压后的文件夹里打开 PowerShell，运行：

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-claude-notify.ps1
   ```

3. 打开一个新的 Claude Code 会话即生效。

安装脚本会把脚本复制到 `%USERPROFILE%\.claude\hooks\`，把 hooks 合并进 `%USERPROFILE%\.claude\settings.json`（自动备份）；重复运行不会重复添加，旧版（v1）安装会被原地升级。

### 方式 B：手动安装

1. 把 `claude-notify.ps1` 和 `stopfailure-launcher.cmd` 一起复制到 `C:\Users\<你>\.claude\hooks\`（没有就新建）；
2. 把 `settings-hooks-snippet.json` 合并进 `C:\Users\<你>\.claude\settings.json`，把 `<USER>` 替换为你的用户名。两个脚本文件本体都不用改 —— 启动器会自动找它旁边的脚本。

## 验证 / 排查

- 随便发一句话，回复结束后应弹「任务完成」；
- 触发选择题框或权限框，应立即弹「在等你...」；
- 排查：`claude --debug hooks`；通知脚本的本地日志在 `%LOCALAPPDATA%\claude-notify\debug.log`。

## 常见问题

- **完全没通知**：系统设置 → 通知 → 确认 "Windows PowerShell" 未被关闭、勿扰模式已关；
- **下载后提示"文件被阻止"**：右键文件 → 属性 → 勾选"解除锁定"；
- **通知文字乱码**：确认脚本保持 UTF-8（带 BOM）编码。

## 从 v1 升级

再运行一次安装脚本即可：旧条目会被原地替换（含匹配规则更新），你自己的其它钩子不受影响。

## 卸载

1. 删除 `settings.json` 中对应的六条 hooks（或整个 `hooks` 键，若无其它钩子）；
2. 删除 `%USERPROFILE%\.claude\hooks\` 下的 `claude-notify.ps1` 和 `stopfailure-launcher.cmd`。

## 工作原理

```
Claude Code 钩子事件
  |- Stop / PreToolUse / PermissionRequest / Elicitation / Notification
  |     -> powershell.exe -File claude-notify.ps1   （读取 JSON，弹窗）
  |- StopFailure
        -> cmd 启动器 -> 分离进程 -> 弹窗
```

使用的事件：`Stop`、`PreToolUse`（AskUserQuestion / ExitPlanMode）、`PermissionRequest`、`StopFailure`、`Elicitation`、`Notification`（权限提示、后台会话、限额通知）。

## 限制

- 仅支持 Windows；
- 通知显示名是 "Windows PowerShell"（系统内置 AUMID）；
- Esc 手动中断、进程崩溃无法通知（官方没有对应事件）；
- 每轮回复都会通知，多窗口会分别弹。

## 许可证

[MIT](LICENSE)
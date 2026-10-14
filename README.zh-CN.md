# claude-code-windows-toast

[English](README.md) | **简体中文**

给 **Claude Code** 加上 Windows 原生 Toast 通知 —— 任务完成、等待你选择、等待你批准时，右下角自动弹提醒。

支持 **Claude Code CLI** 和 **VS Code 插件**（两者共享同一份 `~/.claude/settings.json`）。零依赖：只用 Windows 自带的 PowerShell 5.1 和系统原生 WinRT Toast API。

> 社区非官方项目，与 Anthropic 无关。

## 效果

| 触发时机 | 通知内容 |
| --- | --- |
| 任务完成（主任务回复结束） | `[项目名] 任务完成` + 最后回复摘要 |
| 弹出选择题框 / 计划确认框（`AskUserQuestion` / `ExitPlanMode`） | `[项目名] 在等你选择` |
| 即将弹出权限批准框（`PermissionRequest`） | `[项目名] 在等你批准：<工具名>` |
| MCP 表单 / URL 请求 | `[项目名] 需要你操作`（约 6 秒后） |

- **原生**：调用 Windows 通知 API，无第三方模块、无后台服务。
- **安全**：hook 脚本从不向 stdout 输出、始终 exit 0，绝不会误允许或误拦截任何操作。
- **轻量**：每轮结束增加约 0.5 秒延迟（可改为完全异步）。

## 环境要求

- Windows 10 / 11
- Claude Code（CLI 或 VS Code 插件，任一即可）—— 测试版本 v2.1.296
- Windows PowerShell 5.1（系统自带）

## 安装

### 方式 A：一键安装（推荐）

1. 下载本仓库（**Code → Download ZIP**）或 Release 包；
2. 在解压后的文件夹里打开 PowerShell，运行：

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-claude-notify.ps1
   ```

3. 打开一个新的 Claude Code 会话即生效。

安装脚本会把 `claude-notify.ps1` 复制到 `%USERPROFILE%\.claude\hooks\`，把 hooks 合并进 `%USERPROFILE%\.claude\settings.json`，并自动备份原文件；重复运行不会重复添加。

### 方式 B：手动安装

1. 把 `claude-notify.ps1` 复制到 `C:\Users\<你>\.claude\hooks\`（没有就新建）；
2. 把 `settings-hooks-snippet.json` 合并进 `C:\Users\<你>\.claude\settings.json`，并把 `<USER>` 替换为你的实际用户路径。

## 验证

- 随便发一句话，回复结束后应弹出「任务完成」；
- 触发选择题框或权限框，应立即弹出「在等你…」；
- 排查：`claude --debug hooks`。

## 常见问题

- **完全没通知**：系统设置 → 通知 → 确认 "Windows PowerShell" 未被关闭、勿扰模式已关；
- **下载后提示“文件被阻止”**：右键文件 → 属性 → 勾选“解除锁定”；
- **通知文字乱码**：确认脚本保持 UTF-8（带 BOM）编码。

## 自定义

- 修改 `claude-notify.ps1` 里的文案；
- 想弹框零延迟：给对应 hook 加 `"async": true`；
- 想让通知显示为 "Claude Code" 而不是 "Windows PowerShell"：需要注册自定义 AUMID（可作后续增强）。

## 卸载

1. 删除 `settings.json` 中对应的四条 hooks（或整个 `hooks` 键，若无其它钩子）；
2. 删除 `%USERPROFILE%\.claude\hooks\claude-notify.ps1`。

## 工作原理

```
Claude Code 事件 ──▶ hook 命令（powershell.exe -File claude-notify.ps1）
                       │  从 stdin 读取事件 JSON
                       └─▶ WinRT ToastNotificationManager.Show()
```

使用的 hook 事件：

| 事件 | 用途 |
| --- | --- |
| `Stop` | 主任务回复结束 |
| `PreToolUse`（`AskUserQuestion\|ExitPlanMode`） | 选择题 / 计划确认框出现前 |
| `PermissionRequest` | 权限批准框出现前 |
| `Notification`（`elicitation_dialog\|elicitation_url_dialog`） | MCP 表单 |

## 限制

- 仅支持 Windows；
- 通知显示名是 "Windows PowerShell"（系统内置 AUMID）；
- 每轮回复都会通知，多窗口会分别弹；
- Esc 手动中断不会触发完成通知（Claude Code 行为）；
- 沙箱命令的网络请求提示暂未覆盖（需要时加一行 matcher 即可）。

## 许可证

[MIT](LICENSE)
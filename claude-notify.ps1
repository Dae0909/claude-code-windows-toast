# claude-notify.ps1 — Claude Code hook -> Windows 原生 Toast 通知
# 项目主页 (Project): https://github.com/Dae0909/claude-code-windows-toast
# 由 Claude Code hooks 调用：从 stdin 读取 hook JSON，弹右下角通知后退出。
# 设计约束：不向 stdout 输出任何内容、始终 exit 0（避免干扰 hook 决策）。

$ErrorActionPreference = 'SilentlyContinue'

$raw  = ''
$data = $null
try {
  if ([Console]::IsInputRedirected) {
    $stdin = [Console]::OpenStandardInput()
    $ms = New-Object System.IO.MemoryStream
    $stdin.CopyTo($ms)
    $raw = [Text.Encoding]::UTF8.GetString($ms.ToArray()).TrimStart([char]0xFEFF)
  }
  if ($raw -and $raw.Trim()) { $data = $raw | ConvertFrom-Json }
} catch {}

$folder = ''
try { if ($data.cwd) { $folder = Split-Path -Leaf $data.cwd } } catch {}

$event = ''
try { $event = [string]$data.hook_event_name } catch {}

$title = 'Claude Code'
$body  = '任务完成'
switch ($event) {
  'PreToolUse' {
    $tool = ''
    try { $tool = [string]$data.tool_name } catch {}
    if ($tool -eq 'ExitPlanMode') { $body = '在等你确认计划' }
    elseif ($tool -eq 'AskUserQuestion') { $body = '在等你选择' }
    else { $body = '在等你操作' }
  }
  'PermissionRequest' {
    $tool = ''
    try { $tool = [string]$data.tool_name } catch {}
    if ($tool) { $body = "在等你批准：$tool" } else { $body = '在等你批准' }
  }
  'Notification' { $body = '需要你操作' }
  'StopFailure'  { $body = '任务出错' }
  'Stop' {
    try {
      if ($data.last_assistant_message) {
        $preview = ([string]$data.last_assistant_message -replace '\s+', ' ').Trim()
        if ($preview.Length -gt 80) { $preview = $preview.Substring(0, 80) + '…' }
        if ($preview) { $body = "任务完成`n$preview" }
      }
    } catch {}
  }
}
if ($folder) { $body = "[$folder] $body" }

try {
  [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
  [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

  $titleX = [System.Security.SecurityElement]::Escape($title)
  $bodyX  = [System.Security.SecurityElement]::Escape($body)

  $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
  $xml.LoadXml("<toast><visual><binding template=`"ToastGeneric`"><text>$titleX</text><text>$bodyX</text></binding></visual></toast>")

  $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
  $aumid = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
  [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($aumid).Show($toast)
} catch {}

exit 0
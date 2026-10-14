# claude-notify.ps1 — Claude Code hook -> Windows 原生 Toast 通知（本地增强版 v2.2）
# 项目主页 (Project): https://github.com/Dae0909/claude-code-windows-toast
# 覆盖事件：Stop / StopFailure / PreToolUse / PermissionRequest / Elicitation / Notification
# StopFailure 经 stopfailure-launcher.cmd 分离进程弹出（避免 -p 模式钩子被提前终止）
# 设计约束：不向 stdout 输出任何内容、始终 exit 0（避免干扰 hook 决策）。

param([string]$PayloadFile = '')

$ErrorActionPreference = 'SilentlyContinue'

# ---------- 调试日志（本地文件，仅用于排查；不影响行为） ----------
$dbgDir = $env:LOCALAPPDATA
if (-not $dbgDir) { $dbgDir = $env:TEMP }
$dbgFile = ''
try { $dbgFile = Join-Path $dbgDir 'claude-notify\debug.log' } catch {}
function DBG([string]$m) {
  try {
    if (-not $dbgFile) { return }
    $d = Split-Path -Parent $dbgFile
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    [IO.File]::AppendAllText($dbgFile, ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') + ' ' + $m + "`r`n"), [Text.UTF8Encoding]::new($false))
  } catch {}
}
trap { DBG ('TRAP: ' + $_.Exception.Message + ' @line ' + $_.InvocationInfo.ScriptLineNumber); exit 0 }
DBG ('start ps=' + $PSVersionTable.PSVersion.ToString() + ' inredir=' + [Console]::IsInputRedirected + ' payload=' + $PayloadFile)

# ---------- 读取 hook 输入（UTF-8；优先从 -PayloadFile 读，否则从 stdin 读） ----------
$raw  = ''
$data = $null
try {
  if ($PayloadFile -and (Test-Path -LiteralPath $PayloadFile)) {
    $raw = [IO.File]::ReadAllText($PayloadFile)
    try { Remove-Item -LiteralPath $PayloadFile -Force } catch {}
  } elseif ([Console]::IsInputRedirected) {
    $stdin = [Console]::OpenStandardInput()
    $ms = New-Object System.IO.MemoryStream
    $stdin.CopyTo($ms)
    $raw = [Text.Encoding]::UTF8.GetString($ms.ToArray()).TrimStart([char]0xFEFF)
  }
  if ($raw -and $raw.Trim()) { $data = $raw | ConvertFrom-Json }
} catch { DBG ('stdin EX: ' + $_.Exception.Message) }

function Get-Field([string]$name) {
  try { if ($null -ne $data.$name) { return [string]$data.$name } } catch {}
  return ''
}

$event  = Get-Field 'hook_event_name'
$folder = ''
try { if ($data.cwd) { $folder = Split-Path -Leaf $data.cwd } } catch {}
DBG ('stdin len=' + $raw.Length + ' event=' + $event)

# ---------- 权限提醒去重状态 ----------
$stateRoot = $env:LOCALAPPDATA
if (-not $stateRoot) { $stateRoot = $env:TEMP }
$stateFile = Join-Path $stateRoot 'claude-notify\last-perm-toast.txt'

function Get-PermToastAgeSeconds() {
  try {
    if (Test-Path -LiteralPath $stateFile) {
      $ts = [long]((Get-Content -LiteralPath $stateFile -Raw).Trim())
      return ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $ts)
    }
  } catch {}
  return 999999
}
function Set-PermToastNow() {
  try {
    $dir = Split-Path -Parent $stateFile
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($stateFile, [string][DateTimeOffset]::UtcNow.ToUnixTimeSeconds(), [Text.UTF8Encoding]::new($false))
  } catch {}
}

# ---------- 根据事件生成文案 ----------
$title    = 'Claude Code'
$body     = '状态更新'
$suppress = $false

switch ($event) {
  'PreToolUse' {
    $tool = Get-Field 'tool_name'
    if ($tool -eq 'ExitPlanMode')        { $body = '在等你确认计划' }
    elseif ($tool -eq 'AskUserQuestion') { $body = '在等你选择' }
    else                                 { $body = '在等你操作' }
  }
  'PermissionRequest' {
    $tool = Get-Field 'tool_name'
    if ($tool) { $body = "在等你批准：$tool" } else { $body = '在等你批准' }
    Set-PermToastNow
  }
  'Elicitation' {
    $server = Get-Field 'mcp_server_name'
    $mode   = Get-Field 'mode'
    if ($mode -eq 'url') { $body = '需要你打开浏览器完成操作' } else { $body = '在等你填写表单' }
    if ($server) { $body = $body + '（' + $server + '）' }
  }
  'Notification' {
    $nt  = Get-Field 'notification_type'
    $msg = Get-Field 'message'
    switch ($nt) {
      'permission_prompt' {
        if ((Get-PermToastAgeSeconds) -lt 90) { $suppress = $true }
        else { $body = '在等你批准' }
      }
      'agent_needs_input'          { $body = '后台会话在等你输入' }
      'agent_completed'            { $body = '后台会话已结束' }
      'quota_auto_resume_fired'    { $body = '限额已恢复，任务已自动继续' }
      'quota_auto_resume_stale'    { $body = '限额已恢复，等你按回车继续' }
      'quota_auto_resume_disabled' { $body = '限额等待已结束（任务未继续）' }
      'idle_prompt'                { $body = '在等你回来继续' }
      'auth_success'               { $body = '登录/认证完成' }
      default {
        if ($msg) {
          $msg = ($msg -replace '\s+', ' ').Trim()
          if ($msg.Length -gt 80) { $msg = $msg.Substring(0, 80) + '…' }
          $body = $msg
        } else { $body = '需要你操作' }
      }
    }
  }
  'StopFailure' {
    $err = Get-Field 'error'
    $map = @{
      'rate_limit'             = '用量限额'
      'overloaded'             = '服务过载'
      'authentication_failed'  = '认证失败'
      'oauth_org_not_allowed'  = '组织访问受限'
      'account_on_hold'        = '账号被暂停'
      'billing_error'          = '计费问题'
      'invalid_request'        = '请求无效'
      'model_not_found'        = '模型不存在'
      'server_error'           = '服务端/连接错误'
      'max_output_tokens'      = '输出达到上限'
      'cloud_credential_error' = '云凭证错误'
      'unknown'                = '未知错误'
    }
    $label = ''
    if ($err) { $label = [string]$map[$err] }
    if (-not $label) { $label = '错误' }
    $errText = Get-Field 'last_assistant_message'
    if ($errText) {
      $errText = ($errText -replace '\s+', ' ').Trim()
      if ($errText.Length -gt 90) { $errText = $errText.Substring(0, 90) + '…' }
      $body = "任务出错 · $label`n$errText"
    } else {
      $body = "任务出错 · $label"
    }
  }
  'Stop' {
    $bg = 0; $crons = 0
    try { if ($data.background_tasks) { $bg = @($data.background_tasks).Count } } catch {}
    try { if ($data.session_crons)    { $crons = @($data.session_crons).Count } } catch {}
    if ($bg -gt 0) {
      $body = "阶段完成 · 还有 $bg 个后台任务在跑"
    } elseif ($crons -gt 0) {
      $body = '阶段完成 · 有定时唤醒'
    } else {
      $body = '任务完成'
      try {
        if ($data.last_assistant_message) {
          $preview = ([string]$data.last_assistant_message -replace '\s+', ' ').Trim()
          if ($preview.Length -gt 80) { $preview = $preview.Substring(0, 80) + '…' }
          if ($preview) { $body = "任务完成`n$preview" }
        }
      } catch {}
    }
  }
}

if ($suppress) { DBG 'suppressed'; exit 0 }
if ($folder) { $body = "[$folder] $body" }
DBG ('show: ' + ($body -replace "`r?`n", ' / '))

# ---------- 弹出 Windows 原生通知 ----------
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
  DBG 'show ok'
} catch { DBG ('toast EX: ' + $_.Exception.Message) }

DBG 'exit0'
exit 0
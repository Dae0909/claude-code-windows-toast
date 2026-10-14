#Requires -Version 5.1
<#
  install-claude-notify.ps1（v2.0.0）
  为当前 Windows 用户安装 Claude Code 的 Windows Toast 通知钩子。

  安装内容（复制到 %USERPROFILE%\.claude\hooks\）：
    - claude-notify.ps1        通知脚本
    - stopfailure-launcher.cmd StopFailure 专用启动器（分离进程，保证非交互模式也能弹窗）
  Hook 事件（合并进 %USERPROFILE%\.claude\settings.json）：
    Stop / PreToolUse / PermissionRequest / StopFailure / Elicitation / Notification
  特性：自动备份 settings.json；可重复运行；从 v1 升级时自动替换旧条目（原地升级）。

  用法（在本文件所在文件夹运行）:
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-claude-notify.ps1
  可选参数:
    -ConfigDir <路径>   指定 Claude Code 配置目录（默认 %USERPROFILE%\.claude）
#>
param(
  [string]$ConfigDir = (Join-Path $env:USERPROFILE '.claude')
)

$ErrorActionPreference = 'Stop'

$srcNotify   = Join-Path $PSScriptRoot 'claude-notify.ps1'
$srcLauncher = Join-Path $PSScriptRoot 'stopfailure-launcher.cmd'
foreach ($f in @($srcNotify, $srcLauncher)) {
  if (-not (Test-Path -LiteralPath $f)) { throw ('缺少文件，请确认它和本安装脚本在同一个文件夹里: ' + $f) }
}

$hooksDir = Join-Path $ConfigDir 'hooks'
New-Item -ItemType Directory -Force -Path $hooksDir | Out-Null
$dstNotify   = Join-Path $hooksDir 'claude-notify.ps1'
$dstLauncher = Join-Path $hooksDir 'stopfailure-launcher.cmd'
Copy-Item -LiteralPath $srcNotify   -Destination $dstNotify   -Force
Copy-Item -LiteralPath $srcLauncher -Destination $dstLauncher -Force
Write-Host ('[1/3] 已复制脚本 -> ' + $hooksDir)

function New-DirectHook([string]$ScriptPath) {
  [pscustomobject]@{
    type    = 'command'
    command = 'powershell.exe'
    args    = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath)
    timeout = 10
  }
}
function New-LauncherHook([string]$LauncherPath) {
  [pscustomobject]@{
    type    = 'command'
    command = 'cmd.exe'
    args    = @('/c', $LauncherPath)
    timeout = 10
  }
}
function Test-IsOurArgs($ArgsList) {
  $a = ''
  if ($ArgsList) { $a = ($ArgsList -join ' ') }
  if ($a -like '*claude-notify.ps1*' -or $a -like '*stopfailure-launcher.cmd*') { return $true }
  return $false
}

$spec = @(
  [pscustomobject]@{ Event = 'Stop';              Matcher = $null; Kind = 'direct' },
  [pscustomobject]@{ Event = 'PreToolUse';        Matcher = 'AskUserQuestion|ExitPlanMode'; Kind = 'direct' },
  [pscustomobject]@{ Event = 'PermissionRequest'; Matcher = $null; Kind = 'direct' },
  [pscustomobject]@{ Event = 'StopFailure';       Matcher = $null; Kind = 'launcher' },
  [pscustomobject]@{ Event = 'Elicitation';       Matcher = $null; Kind = 'direct' },
  [pscustomobject]@{ Event = 'Notification';      Matcher = 'permission_prompt|agent_needs_input|agent_completed|quota_auto_resume_fired|quota_auto_resume_stale|quota_auto_resume_disabled'; Kind = 'direct' }
)

$settingsPath = Join-Path $ConfigDir 'settings.json'
if (Test-Path -LiteralPath $settingsPath) {
  $raw = [IO.File]::ReadAllText($settingsPath)
  try { $settings = $raw | ConvertFrom-Json } catch { throw ('现有 settings.json 不是有效 JSON，已中止（未做任何修改）: ' + $settingsPath) }
  $stamp = Get-Date -Format 'yyyyMMddTHHmmss'
  Copy-Item -LiteralPath $settingsPath -Destination ($settingsPath + '.bak.' + $stamp) -Force
  Write-Host ('[2/3] 已备份 -> ' + $settingsPath + '.bak.' + $stamp)
} else {
  $settings = [pscustomobject]@{}
  Write-Host '[2/3] 未发现 settings.json，将新建。'
}

if (-not $settings.PSObject.Properties['hooks']) {
  $settings | Add-Member -MemberType NoteProperty -Name hooks -Value ([pscustomobject]@{})
}
$hooks = $settings.hooks

$added   = New-Object System.Collections.Generic.List[string]
$updated = New-Object System.Collections.Generic.List[string]
foreach ($s in $spec) {
  $event = $s.Event
  if (-not $hooks.PSObject.Properties[$event]) {
    $hooks | Add-Member -MemberType NoteProperty -Name $event -Value @()
  }
  $arr = @()
  if ($hooks.$event) { $arr = @($hooks.$event) }

  if ($s.Kind -eq 'launcher') { $newCmd = New-LauncherHook $dstLauncher } else { $newCmd = New-DirectHook $dstNotify }

  $existing = $null
  foreach ($g in $arr) {
    if ($g.hooks) {
      foreach ($h in @($g.hooks)) { if (Test-IsOurArgs $h.args) { $existing = $g; break } }
    }
    if ($existing) { break }
  }

  if ($existing) {
    $changed = $false
    foreach ($h in @($existing.hooks)) {
      if (-not (Test-IsOurArgs $h.args)) { continue }
      $oldArgs = ''
      if ($h.args) { $oldArgs = ($h.args -join ' ') }
      if ($h.command -ne $newCmd.command) { $changed = $true }
      if ($oldArgs -ne ($newCmd.args -join ' ')) { $changed = $true }
      $h.command = $newCmd.command
      $h.args    = $newCmd.args
      $h.timeout = $newCmd.timeout
      break
    }
    $curM = ''
    if ($existing.PSObject.Properties['matcher']) { $curM = [string]$existing.matcher }
    $wantM = ''
    if ($s.Matcher) { $wantM = $s.Matcher }
    if ($curM -ne $wantM) { $changed = $true }
    if ($wantM) {
      if ($existing.PSObject.Properties['matcher']) { $existing.matcher = $wantM } else { $existing | Add-Member -MemberType NoteProperty -Name matcher -Value $wantM }
    } else {
      if ($existing.PSObject.Properties['matcher']) { $existing.PSObject.Properties.Remove('matcher') }
    }
    if ($changed) { $updated.Add($event) | Out-Null }
  } else {
    $group = [pscustomobject]@{}
    if ($s.Matcher) { $group | Add-Member -MemberType NoteProperty -Name matcher -Value $s.Matcher }
    $group | Add-Member -MemberType NoteProperty -Name hooks -Value @($newCmd)
    $arr = $arr + $group
    $hooks.PSObject.Properties[$event].Value = $arr
    $added.Add($event) | Out-Null
  }
}

$json = $settings | ConvertTo-Json -Depth 32
[IO.File]::WriteAllText($settingsPath, $json, (New-Object System.Text.UTF8Encoding($false)))

$check = [IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json
if (-not $check.hooks -or -not $check.hooks.StopFailure) { throw '写入校验失败，请检查 settings.json' }

if ($added.Count -eq 0 -and $updated.Count -eq 0) {
  Write-Host '[3/3] 通知 hooks 已是最新，无需变更。'
} else {
  Write-Host ('[3/3] 事件新增: ' + ($added -join ', ') + ' | 更新: ' + ($updated -join ', '))
}
Write-Host '完成。新开一个 Claude Code 会话（终端或 VS Code 插件）即会生效。'
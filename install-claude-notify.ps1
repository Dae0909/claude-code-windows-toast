#Requires -Version 5.1
<#
  install-claude-notify.ps1
  项目主页 (Project): https://github.com/Dae0909/claude-code-windows-toast
  为当前 Windows 用户安装 Claude Code 的 Toast 通知钩子（任务完成 / 等待选择 / 等待批准 等）。

  用法（在本文件所在文件夹运行）:
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-claude-notify.ps1

  可选参数:
    -ConfigDir <路径>   指定 Claude Code 配置目录（默认 %USERPROFILE%\.claude）
#>
param(
  [string]$ConfigDir = (Join-Path $env:USERPROFILE '.claude')
)

$ErrorActionPreference = 'Stop'

$srcScript = Join-Path $PSScriptRoot 'claude-notify.ps1'
if (-not (Test-Path -LiteralPath $srcScript)) {
  throw '找不到 claude-notify.ps1，请确认它和本安装脚本在同一个文件夹里。'
}

$hooksDir = Join-Path $ConfigDir 'hooks'
New-Item -ItemType Directory -Force -Path $hooksDir | Out-Null
$scriptPath = Join-Path $hooksDir 'claude-notify.ps1'
Copy-Item -LiteralPath $srcScript -Destination $scriptPath -Force
Write-Host "[1/3] 已复制通知脚本 -> $scriptPath"

$settingsPath = Join-Path $ConfigDir 'settings.json'
if (Test-Path -LiteralPath $settingsPath) {
  $raw = [IO.File]::ReadAllText($settingsPath)
  try { $settings = $raw | ConvertFrom-Json } catch {
    throw "现有 settings.json 不是有效 JSON，已中止（未做任何修改）: $settingsPath"
  }
  $stamp = Get-Date -Format 'yyyyMMddTHHmmss'
  Copy-Item -LiteralPath $settingsPath -Destination "$settingsPath.bak.$stamp" -Force
  Write-Host "[2/3] 已备份 -> $settingsPath.bak.$stamp"
} else {
  $settings = [pscustomobject]@{}
  Write-Host '[2/3] 未发现 settings.json，将新建。'
}

function New-NotifyCommand([string]$ScriptPath) {
  [pscustomobject]@{
    type    = 'command'
    command = 'powershell.exe'
    args    = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath)
    timeout = 10
  }
}

function Test-HasNotifyHook($Entries) {
  if (-not $Entries) { return $false }
  foreach ($entry in @($Entries)) {
    if (-not $entry.hooks) { continue }
    foreach ($h in @($entry.hooks)) {
      if ($h.args -and (($h.args -join ' ') -like '*claude-notify.ps1*')) { return $true }
    }
  }
  return $false
}

if (-not $settings.PSObject.Properties['hooks']) {
  $settings | Add-Member -MemberType NoteProperty -Name hooks -Value ([pscustomobject]@{})
}
$hooks = $settings.hooks

$spec = @(
  [pscustomobject]@{ Event = 'Stop';              Matcher = $null },
  [pscustomobject]@{ Event = 'PreToolUse';        Matcher = 'AskUserQuestion|ExitPlanMode' },
  [pscustomobject]@{ Event = 'PermissionRequest'; Matcher = $null },
  [pscustomobject]@{ Event = 'Notification';      Matcher = 'elicitation_dialog|elicitation_url_dialog' }
)

$added = New-Object System.Collections.Generic.List[string]
foreach ($s in $spec) {
  $event = $s.Event
  if (-not $hooks.PSObject.Properties[$event]) {
    $hooks | Add-Member -MemberType NoteProperty -Name $event -Value @()
  }
  $arr = @()
  if ($hooks.$event) { $arr = @($hooks.$event) }
  if (Test-HasNotifyHook $arr) { continue }
  $group = [pscustomobject]@{}
  if ($s.Matcher) { $group | Add-Member -MemberType NoteProperty -Name matcher -Value $s.Matcher }
  $group | Add-Member -MemberType NoteProperty -Name hooks -Value @((New-NotifyCommand $scriptPath))
  $arr = $arr + $group
  $hooks.PSObject.Properties[$event].Value = $arr
  $added.Add($event) | Out-Null
}

$json = $settings | ConvertTo-Json -Depth 32
[IO.File]::WriteAllText($settingsPath, $json, (New-Object System.Text.UTF8Encoding($false)))

$check = [IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json
if (-not $check.hooks) { throw '写入校验失败，请检查 settings.json' }

if ($added.Count -eq 0) {
  Write-Host '[3/3] 通知 hooks 已存在，无需重复添加。'
} else {
  Write-Host "[3/3] 已配置 hooks: $($added -join ', ')"
}
Write-Host '完成。新开一个 Claude Code 会话（终端或 VS Code 插件）即会生效。'
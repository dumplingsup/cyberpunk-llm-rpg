param(
  [switch]$Mock,
  [switch]$NoLaunch,
  [switch]$HeadlessTest
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$bridgeUrl = "http://127.0.0.1:8791/health"
$logDir = Join-Path $root "bridge\logs"
New-Item -ItemType Directory -Force $logDir | Out-Null

# Localhost health checks must never go through a system proxy.
function Get-BridgeHealth {
  $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
  if (-not $curl) { $curl = Get-Command curl -ErrorAction SilentlyContinue }
  if ($curl) {
    $raw = & $curl.Source --silent --max-time 2 --noproxy "*" $bridgeUrl 2>$null
    if ($LASTEXITCODE -eq 0 -and $raw) {
      try { return ($raw | ConvertFrom-Json) } catch { return $null }
    }
    return $null
  }
  try {
    $wc = New-Object System.Net.WebClient
    $wc.Proxy = $null
    $raw = $wc.DownloadString($bridgeUrl)
    return ($raw | ConvertFrom-Json)
  } catch { return $null }
}

function Test-Bridge { return $null -ne (Get-BridgeHealth) }

if (-not (Test-Bridge)) {
  Write-Host "[bridge] 启动本地 Pi 桥接服务..." -ForegroundColor Cyan
  if ($Mock) { $env:BRIDGE_MODE = "mock" } else { Remove-Item Env:BRIDGE_MODE -ErrorAction SilentlyContinue }
  $outLog = Join-Path $logDir "bridge.out.log"
  $errLog = Join-Path $logDir "bridge.err.log"
  $p = Start-Process -FilePath "node" -ArgumentList "bridge\server.mjs" -WorkingDirectory $root `
    -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru
  Set-Content -Path (Join-Path $root ".bridge.pid") -Value $p.Id
  $ok = $false
  for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Milliseconds 300
    if (Test-Bridge) { $ok = $true; break }
    if ($p.HasExited) { break }
  }
  if (-not $ok) {
    Write-Host "[bridge] 启动失败。" -ForegroundColor Red
    if (Test-Path $errLog) { Get-Content $errLog -Tail 40 }
    throw "bridge failed to start"
  }
  Write-Host "[bridge] 已就绪 (pid $($p.Id))" -ForegroundColor Green
} else {
  Write-Host "[bridge] 检测到已运行的服务。" -ForegroundColor Green
}

$health = Get-BridgeHealth
if ($health) {
  Write-Host ("[bridge] mode={0} model={1} pi={2}" -f $health.mode, $health.model, $health.piVersion) -ForegroundColor DarkGray
  if ($Mock -and $health.mode -ne "mock") {
    Write-Host "[bridge] 警告：当前服务不是 mock 模式；如需 mock 请先停止已有 bridge。" -ForegroundColor Yellow
  }
}

if ($NoLaunch) { return }

$godotCandidates = @(
  $env:GODOT_EXE,
  "D:\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe",
  "D:\godot\Godot_v4.6.1-stable_win64.exe",
  (Get-Command godot -ErrorAction SilentlyContinue).Source
)
$godot = $godotCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $godot) {
  throw "找不到 Godot 4.6 可执行文件。请设置 GODOT_EXE。"
}
$gamePath = Join-Path $root "game"
$godotArgs = @("--path", $gamePath)
if ($HeadlessTest) { $godotArgs += @("--headless", "--quit-after", "5") }
Write-Host "[game] $godot $($godotArgs -join ' ')" -ForegroundColor Cyan
Start-Process -FilePath $godot -ArgumentList $godotArgs -WorkingDirectory $root | Out-Null
Write-Host "[game] 已启动。关闭游戏窗口即可退出。" -ForegroundColor Green

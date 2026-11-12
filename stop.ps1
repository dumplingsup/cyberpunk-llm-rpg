param([switch]$IncludeGame)
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$pidFile = Join-Path $root ".bridge.pid"
if (Test-Path $pidFile) {
  $bridgePid = Get-Content $pidFile | Select-Object -First 1
  $p = Get-Process -Id $bridgePid -ErrorAction SilentlyContinue
  if ($p) {
    Stop-Process -Id $bridgePid -Force
    Write-Host "[bridge] 已停止 (pid $bridgePid)" -ForegroundColor Yellow
  }
  Remove-Item $pidFile -ErrorAction SilentlyContinue
} else {
  Write-Host "[bridge] 没有 PID 记录。" -ForegroundColor DarkGray
}
if ($IncludeGame) {
  Get-Process | Where-Object { $_.ProcessName -like "Godot*" -and $_.MainWindowTitle -like "*NEON VEIL*" } |
    ForEach-Object { Stop-Process -Id $_.Id -Force; Write-Host "[game] 已停止 (pid $($_.Id))" -ForegroundColor Yellow }
}

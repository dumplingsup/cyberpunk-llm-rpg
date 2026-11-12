param(
  [int]$GamePid = 0,
  [string]$TitleLike = "NEON VEIL",
  [string]$Out = "capture.png"
)
Add-Type @"
using System;
using System.Drawing;
using System.Runtime.InteropServices;
public static class WinCap {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int n);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
[WinCap]::SetProcessDPIAware() | Out-Null

$proc = $null
if ($GamePid -gt 0) {
  $proc = Get-Process -Id $GamePid -ErrorAction SilentlyContinue
} else {
  $proc = Get-Process | Where-Object { $_.MainWindowTitle -like "*$TitleLike*" } | Select-Object -First 1
}
if (-not $proc) { throw "找不到游戏窗口 (pid=$GamePid title=$TitleLike)" }

$h = $proc.MainWindowHandle
if ($h -eq 0) { throw "窗口句柄为空" }
[WinCap]::ShowWindowAsync($h, 9) | Out-Null
[WinCap]::BringWindowToTop($h) | Out-Null
[WinCap]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 700

$r = New-Object WinCap+RECT
[WinCap]::GetWindowRect($h, [ref]$r) | Out-Null
$w = $r.Right - $r.Left
$ht = $r.Bottom - $r.Top
if ($w -le 0 -or $ht -le 0) { throw "窗口尺寸无效: $w x $ht" }
$bmp = New-Object System.Drawing.Bitmap $w, $ht
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.Left, $r.Top, 0, 0, (New-Object System.Drawing.Size $w, $ht))
$dir = Split-Path -Parent $Out
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
"captured $w x $ht -> $Out"

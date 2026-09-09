param([switch]$SkipCompile)
$root = Split-Path $PSScriptRoot

if (-not $SkipCompile) {
    Write-Host "=== Compiling ==="
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "compile-th3.ps1") -Project all 2>&1 |
        Where-Object { $_ -match "Result:|error" } | ForEach-Object { Write-Host "  $_" }
    Write-Host "Compile done."
}

$proc = Get-Process "terminal" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) { Write-Host "MT4 not running"; exit 0 }
$exe  = $proc.Path
$hwnd = $proc.MainWindowHandle
Write-Host "MT4 found: $exe"

$cs = "using System; using System.Runtime.InteropServices; public class WC3 { " +
      "[DllImport(`"user32.dll`")] public static extern bool ShowWindow(IntPtr h,int n); " +
      "[DllImport(`"user32.dll`")] public static extern bool SetForegroundWindow(IntPtr h); " +
      "[DllImport(`"user32.dll`")] public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l); }"
Add-Type -TypeDefinition $cs -ErrorAction SilentlyContinue

Write-Host "=== Closing MT4 (saves charts) ==="
[WC3]::ShowWindow($hwnd, 9) | Out-Null
[WC3]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 400
[WC3]::PostMessage($hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null

$w = 0
while ($w -lt 30) {
    Start-Sleep -Milliseconds 500
    $w++
    if (-not (Get-Process "terminal" -ErrorAction SilentlyContinue)) { break }
}
if (Get-Process "terminal" -ErrorAction SilentlyContinue) {
    Stop-Process -Name "terminal" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}
Write-Host "MT4 closed. Restarting..."
Start-Process -FilePath $exe
Write-Host "Waiting 20 s for MT4 + indicators to load..."
Start-Sleep -Seconds 20
Write-Host "Fetching log..."
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "fetch_tradeplan_log.ps1")

# TEMP probe (not part of the product): the chip-move reproduction harness.
#
# The user's scenario is «باز و بستن متاتریدر» — a graceful CLOSE and reopen. The bug is
# that the chip's stored home fraction is rewritten across that cycle, so the chip lands
# somewhere else. This harness measures the exact cycle and reports two independent kinds
# of evidence:
#   * the STORE (`profiles/gvariables.dat`) — the BIOMENU_HOME_* fractions, read before
#     and after each close. This is the cause, at byte level.
#   * the PIXELS — a PNG of the terminal window at the same two moments.
#
# `Start-Process` dies when both cases of a proxy variable are present (its child env is a
# case-insensitive dictionary), so the four names are removed from THIS process first.
param(
    [string]$OutDir = "$env:TEMP\chipcycle",
    [int]$SettleSec = 30,
    [int]$ShutdownSec = 45
)
$ErrorActionPreference = 'Continue'
foreach ($n in 'HTTP_PROXY', 'http_proxy', 'HTTPS_PROXY', 'https_proxy') {
    [Environment]::SetEnvironmentVariable($n, $null, 'Process')
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$log = Join-Path $OutDir 'report.txt'
Remove-Item $log -ErrorAction SilentlyContinue
function Say($m) { $m | Out-File -Append -Encoding utf8 $log }

$STORE = 'C:\Users\Bioootak\AppData\Roaming\MetaQuotes\Terminal\A1660DA4CB596E740BE3B3233E577E1B\profiles\gvariables.dat'
$PY = 'C:\Users\Bioootak\.workbuddy-ai\binaries\python\versions\3.13.12\python.exe'
$GVR = 'C:\Users\Bioootak\Desktop\Trading\Biotak-Trigger-TH3-mql4\tools\_gvread.py'

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinCap {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L; public int T; public int R; public int B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
"@

function Get-Term {
    $p = Get-Process -Name terminal -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    return $p
}
function Get-TermCmd {
    $c = Get-CimInstance Win32_Process -Filter "Name='terminal.exe'" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.CommandLine }
    return $null
}
function Snap([string]$tag) {
    $p = Get-Term
    if (-not $p) { Say ("snap {0}: NO WINDOW" -f $tag); return }
    $h = $p.MainWindowHandle
    [WinCap]::SetForegroundWindow($h) | Out-Null
    Start-Sleep -Milliseconds 700
    $r = New-Object WinCap+RECT
    [WinCap]::GetWindowRect($h, [ref]$r) | Out-Null
    $w = $r.R - $r.L; $hh = $r.B - $r.T
    if ($w -le 0 -or $hh -le 0) { Say ("snap {0}: bad rect" -f $tag); return }
    $bmp = New-Object System.Drawing.Bitmap $w, $hh
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
    $path = Join-Path $OutDir ("shot_{0}.png" -f $tag)
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Say ("snap {0}: rect=({1},{2}) {3}x{4} -> {5}" -f $tag, $r.L, $r.T, $w, $hh, $path)
}
function DumpStore([string]$tag) {
    Say ("--- store @ {0} (mtime {1}) ---" -f $tag, (Get-Item $STORE).LastWriteTime.ToString('HH:mm:ss'))
    $out = & $PY $GVR $STORE 2>&1 | Select-String 'HOME_(CHIP|ORB|STRIP)_(FX|FY)'
    foreach ($l in $out) { Say ("    " + $l.ToString().Trim()) }
}
function GracefulClose {
    $p = Get-Term
    if (-not $p) { Say 'close: no process'; return }
    $h = $p.MainWindowHandle
    [void]$p.CloseMainWindow()
    $deadline = (Get-Date).AddSeconds($ShutdownSec)
    while ((Get-Date) -lt $deadline) {
        if ((Get-Process -Id $p.Id -ErrorAction SilentlyContinue) -eq $null) { Say 'close: exited cleanly'; return }
        Start-Sleep -Milliseconds 500
    }
    Say 'close: STILL RUNNING after timeout (left alone)'
}

$exe = (Get-TermCmd)
Say ("=== chip cycle start {0} ===" -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
Say ("terminal command line: {0}" -f $exe)
if (-not $exe) { Say 'FATAL: cannot read the terminal command line'; exit 3 }

#--- 1. the state as the running session leaves it
Snap 'a_running'
DumpStore 'a_running'

#--- 2. graceful close = the user's «بستن متاتریدر». This is the moment the store flushes.
GracefulClose
Start-Sleep -Seconds 2
DumpStore 'b_after_close1'

#--- 3. reopen and let every indicator attach (this is where the old code poisoned it)
$exePath = $null
if ($exe -match '^\s*"?(.*?\.exe)') { $exePath = $Matches[1].Trim('"') }
if (-not $exePath -or -not (Test-Path $exePath)) {
    #--- the CIM read needs a privilege this shell may not hold; the process's own image
    #--- path answers without it, and the build log names the same file.
    $p = Get-Term
    if ($p -and $p.Path -and (Test-Path $p.Path)) { $exePath = $p.Path }
}
if (-not $exePath -or -not (Test-Path $exePath)) {
    $guess = 'C:\Program Files (x86)\AMarkets - MetaTrader 4\terminal.exe'
    if (Test-Path $guess) { $exePath = $guess }
}
if (-not $exePath -or -not (Test-Path $exePath)) { Say ("FATAL: cannot resolve exe from '{0}'" -f $exe); exit 3 }
Say ("relaunch: {0}" -f $exePath)
Start-Process -FilePath $exePath | Out-Null
Start-Sleep -Seconds $SettleSec
Snap 'c_reopened'
DumpStore 'c_reopened'

#--- 4. close AGAIN: the session that just attached writes what it decided
GracefulClose
Start-Sleep -Seconds 2
DumpStore 'd_after_close2'

#--- 5. leave the terminal running for the user
Start-Process -FilePath $exePath | Out-Null
Start-Sleep -Seconds $SettleSec
Snap 'e_final'
Say ("=== chip cycle end {0} ===" -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))

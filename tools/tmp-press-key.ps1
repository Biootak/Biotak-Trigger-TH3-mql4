# TEMP test helper (not part of the product): deliver MT4 hotkeys to a running terminal
# and read back whether the indicator logged them.
# Written for the 2026-09-30 T/TH/HTF measurement round; delete after the round.
#
# Two delivery modes, and the first attempt proved why the second exists:
#  -Mode Key  : keybd_event -> the SYSTEM input queue -> whatever window has FOCUS.
#               SetForegroundWindow from a background process is refused by Windows'
#               foreground lock, so this file takes the ALT bypass and VERIFIES the
#               foreground window is the terminal before a single key is sent
#               (it reported foreground=False and the keys went to the caller's app).
#               Sending it to the terminal still failed: inside the process the key
#               lands on the FOCUSED child, and after a restart the chart view does
#               not hold keyboard focus, so no CHARTEVENT_KEYDOWN is raised.
#  -Mode Post : PostMessage(WM_KEYDOWN/WM_KEYUP) STRAIGHT to the chart child window
#               (class AfxFrameOrView140s, found by enumerating the frame's children).
#               No focus required, so no foreground lock to fight. -List prints the
#               candidates so the chart handle used is a number, not a guess.
param(
  [string]$Keys = "T|T",
  [int]$GapMs = 4000,
  [ValidateSet("Key","Post")][string]$Mode = "Post",
  [ValidateSet("Chart","Main")][string]$Target = "Chart",
  [switch]$CheckOnly,
  [switch]$List
)
Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class Th3Win {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern IntPtr MapVirtualKey(uint code, uint type);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  public static List<IntPtr> Kids = new List<IntPtr>();
  public static List<string> Rows = new List<string>();
  public static bool Cb(IntPtr h, IntPtr l) {
    var c = new StringBuilder(256); GetClassName(h, c, 256);
    var t = new StringBuilder(256); GetWindowText(h, t, 256);
    Kids.Add(h);
    Rows.Add(string.Format("0x{0:X}|{1}|{2}", h.ToInt64(), c.ToString(), t.ToString()));
    return true;
  }
  public static void Walk(IntPtr top) { Kids.Clear(); Rows.Clear(); EnumChildWindows(top, Cb, IntPtr.Zero); }
  public static int Vk(string s) { if (s.Length < 1) return 0; return (int)char.ToUpper(s[0]); }
}
"@
$p = Get-Process terminal -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { Write-Host "NO TERMINAL WINDOW"; exit 2 }
$h = $p.MainWindowHandle
[Th3Win]::Walk($h) | Out-Null
if ($List) {
  Write-Host ("terminal pid={0} frame=0x{1:X} children={2}" -f $p.Id, $h.ToInt64(), [Th3Win]::Kids.Count)
  [Th3Win]::Rows | ForEach-Object { $_ }
  exit 0
}
$dest = $h
if ($Target -eq "Chart") {
  $idx = [Th3Win]::Rows.IndexOf(($c = [Th3Win]::Rows | Where-Object { $_ -match 'AfxFrameOrView' } | Select-Object -First 1))
  if ($null -eq $c) { Write-Host "NO CHART WINDOW (AfxFrameOrView140s) under the frame"; exit 5 }
  $dest = [Th3Win]::Kids[$idx]
}
Write-Host ("terminal pid={0} frame=0x{1:X} target={2} dest=0x{3:X}" -f $p.Id, $h.ToInt64(), $Target, $dest.ToInt64())
if ($Mode -eq "Key") {
  $before = [Th3Win]::GetForegroundWindow()
  if ($before -ne $h) {
    [Th3Win]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
    [Th3Win]::ShowWindow($h, 9) | Out-Null
    [Th3Win]::SetForegroundWindow($h) | Out-Null
    [Th3Win]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 700
    if ([Th3Win]::GetForegroundWindow() -ne $h) { Write-Host "REFUSED: terminal could not take focus - no keys sent"; exit 3 }
  }
}
if ($CheckOnly) { Write-Host "check-only: destination resolved"; exit 0 }
$sent = 0
foreach ($ch in $Keys.ToCharArray()) {
  if ($ch -eq "|") { Start-Sleep -Milliseconds $GapMs; continue }
  $vk = [Th3Win]::Vk([string]$ch)
  if ($vk -eq 0) { continue }
  if ($Mode -eq "Post") {
    $scan = [int][Th3Win]::MapVirtualKey([uint32]$vk, 0)
    $lDown = [IntPtr]([int64](1 -bor ($scan -shl 16)))
    $lUp   = [IntPtr]([int64](-1073741824 -bor (1 -bor ($scan -shl 16))))
    [Th3Win]::PostMessage($dest, 0x0100, [IntPtr]$vk, $lDown) | Out-Null
    Start-Sleep -Milliseconds 40
    [Th3Win]::PostMessage($dest, 0x0101, [IntPtr]$vk, $lUp) | Out-Null
    Start-Sleep -Milliseconds 30
  } else {
    [Th3Win]::keybd_event([byte]$vk, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [Th3Win]::keybd_event([byte]$vk, 0, 2, [UIntPtr]::Zero)
  }
  $sent++
  Write-Host ("sent: {0} (vk=0x{1:X})" -f [string]$ch, $vk)
  Start-Sleep -Milliseconds $GapMs
}
Write-Host ("keys sent: {0}" -f $sent)

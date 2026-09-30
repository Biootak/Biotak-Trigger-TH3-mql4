# TEMP test helper (not part of the product); delete after the 2026-09-30 measurement round.
#
# WHY: MT4 buffers the Experts log in memory and the on-disk MQL4\Logs\<date>.log can sit
# stale for many minutes. `dir` proves it: at 09:30 the file still had the 09:13:12 mtime
# while the chart was live. The Terminal panel's lists hold the SAME lines already, so a
# non-invasive read of the list view is the honest reading of "what did the indicator print".
#
# LVM_GETITEMTEXT needs a buffer inside the TARGET process, so this uses the standard
# VirtualAllocEx / WriteProcessMemory / SendMessage / ReadProcessMemory handshake.
param(
  [string]$Hwnd = "",
  [int]$Last = 12,
  [switch]$List
)
Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class Mt4Tail {
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumProc cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(uint acc, bool inh, uint pid);
  [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll")] public static extern IntPtr VirtualAllocEx(IntPtr p, IntPtr addr, IntPtr size, uint type, uint prot);
  [DllImport("kernel32.dll")] public static extern bool VirtualFreeEx(IntPtr p, IntPtr addr, IntPtr size, uint type);
  [DllImport("kernel32.dll")] public static extern bool WriteProcessMemory(IntPtr p, IntPtr addr, byte[] buf, IntPtr n, IntPtr written);
  [DllImport("kernel32.dll")] public static extern bool ReadProcessMemory(IntPtr p, IntPtr addr, byte[] buf, IntPtr n, IntPtr read);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  public static List<IntPtr> Kids = new List<IntPtr>();
  public static bool Cb(IntPtr h, IntPtr l) { Kids.Add(h); return true; }
  public const uint LVM_GETITEMCOUNT = 0x1004;
  public const uint LVM_GETITEMTEXTW = 0x1073;
  public const uint LVIF_TEXT = 0x0001;
  public static byte[] Item(int idx, int sub, long remoteText, int cch) {
    var b = new byte[128];
    BitConverter.GetBytes(LVIF_TEXT).CopyTo(b, 0);
    BitConverter.GetBytes(idx).CopyTo(b, 4);
    BitConverter.GetBytes(sub).CopyTo(b, 8);
    BitConverter.GetBytes(remoteText).CopyTo(b, 24);
    BitConverter.GetBytes(cch).CopyTo(b, 32);
    return b;
  }
  public static string Cell(IntPtr proc, IntPtr pItem, IntPtr list, int idx, int sub, long remoteText, int cch) {
    var bytes = Item(idx, sub, remoteText, cch);
    WriteProcessMemory(proc, pItem, bytes, (IntPtr)bytes.Length, IntPtr.Zero);
    SendMessage(list, LVM_GETITEMTEXTW, (IntPtr)idx, pItem);
    return Text(proc, remoteText, cch);
  }
  public static string Text(IntPtr proc, long remoteText, int cch) {
    var buf = new byte[cch * 2];
    if (!ReadProcessMemory(proc, (IntPtr)remoteText, buf, (IntPtr)buf.Length, IntPtr.Zero)) return "<read failed>";
    var s = Encoding.Unicode.GetString(buf);
    int z = s.IndexOf('\0');
    return (z >= 0 ? s.Substring(0, z) : s);
  }
}
"@
$p = Get-Process terminal -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { Write-Host "NO TERMINAL WINDOW"; exit 2 }
[Mt4Tail]::Kids.Clear()
[Mt4Tail]::EnumChildWindows($p.MainWindowHandle, [Mt4Tail+EnumProc]{ param($a,$b) [Mt4Tail]::Cb($a,$b) }, [IntPtr]::Zero) | Out-Null
$lists = @()
foreach ($k in [Mt4Tail]::Kids) {
  $c = New-Object System.Text.StringBuilder 128; [Mt4Tail]::GetClassName($k, $c, 128) | Out-Null
  if ($c.ToString() -eq 'SysListView32') {
    $n = [Mt4Tail]::SendMessage($k, [Mt4Tail]::LVM_GETITEMCOUNT, [IntPtr]::Zero, [IntPtr]::Zero).ToInt64()
    $lists += [pscustomobject]@{ Hwnd=$k; Count=$n; Visible=([Mt4Tail]::IsWindowVisible($k)) }
  }
}
if ($List) { $lists | ForEach-Object { Write-Host ("LIST 0x{0:X} items={1} visible={2}" -f $_.Hwnd.ToInt64(), $_.Count, $_.Visible) }; exit 0 }
$targets = $lists
if ($Hwnd -ne "") { $targets = $lists | Where-Object { ("0x{0:X}" -f $_.Hwnd.ToInt64()) -eq $Hwnd.ToUpper() } }
$proc = [Mt4Tail]::OpenProcess(0x0038, $false, [uint32]$p.Id)   # VM_OPERATION|VM_READ|VM_WRITE
if ($proc -eq [IntPtr]::Zero) { Write-Host "OpenProcess failed"; exit 6 }
$pItem = [Mt4Tail]::VirtualAllocEx($proc, [IntPtr]::Zero, [IntPtr]1024, 0x3000, 0x04)
$pText = [Mt4Tail]::VirtualAllocEx($proc, [IntPtr]::Zero, [IntPtr]8192, 0x3000, 0x04)
if ($pItem -eq [IntPtr]::Zero -or $pText -eq [IntPtr]::Zero) { Write-Host "VirtualAllocEx failed"; exit 7 }
foreach ($t in $targets) {
  if ($t.Count -le 0) { continue }
  Write-Host ("=== LIST 0x{0:X} items={1} visible={2} ===" -f $t.Hwnd.ToInt64(), $t.Count, $t.Visible)
  $from = [Math]::Max(0, $t.Count - $Last)
  for ($i = $from; $i -lt $t.Count; $i++) {
    $c0 = [Mt4Tail]::Cell($proc, $pItem, $t.Hwnd, $i, 0, $pText.ToInt64(), 2000)
    $c1 = [Mt4Tail]::Cell($proc, $pItem, $t.Hwnd, $i, 1, $pText.ToInt64(), 2000)
    if ($c1.Length -gt 0) { Write-Host ("{0,6}| {1} || {2}" -f $i, $c0, $c1) }
    else { Write-Host ("{0,6}| {1}" -f $i, $c0) }
  }
}
[Mt4Tail]::VirtualFreeEx($proc, $pItem, [IntPtr]::Zero, 0x8000) | Out-Null
[Mt4Tail]::VirtualFreeEx($proc, $pText, [IntPtr]::Zero, 0x8000) | Out-Null
[Mt4Tail]::CloseHandle($proc) | Out-Null

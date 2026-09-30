# TEMP test helper (not part of the product); delete after the 2026-09-30 measurement round.
#
# Reading MT4's own log out of the Terminal panel, non-invasively:
#  - LVM_GETITEMTEXT returns empty for MT4's log lists (they are drawn by the app), so the
#    item-text route is dead (proved with tmp-mt4-tail.ps1: 2993/459 items, all blank).
#  - The counted route that DOES work is the app's own copy: Ctrl+A then Ctrl+C on the
#    log list, then read the Windows clipboard. The clipboard is overwritten, so the
#    previous value is printed first (it is restored at the end when it is plain text).
param(
  [string]$Hwnd = "0x5050C",
  [int]$Tail = 60
)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Mt4Keys {
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
}
"@
$num = ($Hwnd -replace '^0[xX]', '')
$dest = [IntPtr][int64]([Convert]::ToInt64($num, 16))
if (-not [Mt4Keys]::IsWindow($dest)) { Write-Host ("NOT A WINDOW: {0}" -f $Hwnd); exit 2 }
$dn = [IntPtr]([int64]1)
$up = [IntPtr]([int64](-1073741823))
$VK_CTRL = 0x11; $VK_A = 0x41; $VK_C = 0x43
function Combo([int]$vk) {
  [Mt4Keys]::PostMessage($dest, 0x0100, [IntPtr]$VK_CTRL, $dn) | Out-Null
  Start-Sleep -Milliseconds 40
  [Mt4Keys]::PostMessage($dest, 0x0100, [IntPtr]$vk, $dn) | Out-Null
  Start-Sleep -Milliseconds 40
  [Mt4Keys]::PostMessage($dest, 0x0101, [IntPtr]$vk, $up) | Out-Null
  Start-Sleep -Milliseconds 40
  [Mt4Keys]::PostMessage($dest, 0x0101, [IntPtr]$VK_CTRL, $up) | Out-Null
  Start-Sleep -Milliseconds 300
}
$before = $null
try { $before = Get-Clipboard -Raw -ErrorAction Stop } catch { }
try { Set-Clipboard -Value "MT4-TAIL-PROBE-EMPTY" -ErrorAction Stop; $hadBefore = $true } catch { $hadBefore = $false }
Combo $VK_A
Combo $VK_C
Start-Sleep -Milliseconds 900
$txt = ""
try { $txt = Get-Clipboard -Raw -ErrorAction Stop } catch { }
if ($null -eq $txt) { $txt = "" }
Write-Host ("hwnd={0} clipboard chars={1}" -f $Hwnd, $txt.Length)
if ($txt.Trim().Length -eq 0 -or $txt -match '^MT4-TAIL-PROBE-EMPTY') {
  Write-Host "COPY PRODUCED NOTHING - the list did not answer Ctrl+A/Ctrl+C"
  exit 3
}
$lines = $txt -split "`r`n|`n"
if ($lines.Count -gt $Tail) { $lines = $lines[($lines.Count - $Tail)..($lines.Count - 1)] }
$lines | ForEach-Object { Write-Host $_ }
if ($hadBefore -and $before -and $before.Length -gt 0) {
  try { Set-Clipboard -Value $before -ErrorAction Stop } catch { }
}

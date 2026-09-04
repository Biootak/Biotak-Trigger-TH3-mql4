<#
.SYNOPSIS
    Orb preview refresher (ASCII-only; the HTML holds all Persian text).
    Decodes Files/Icons/orb_bg.bmp (72x72 premultiplied BGRA) to
    tools/orb-bg-72.png, decodes tools/orb-bow-master.bgra to the
    preview-only tools/orb-candidate-72.png, and stamps build info into
    tools/orb-preview.html (idempotent span rewrite).
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-orb-preview.ps1
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$Root   = Split-Path -Parent $PSScriptRoot
$Bmp    = Join-Path $Root 'Files\Icons\orb_bg.bmp'
$OutPng = Join-Path $PSScriptRoot 'orb-bg-72.png'
$OutHtml= Join-Path $PSScriptRoot 'orb-preview.html'

if (-not (Test-Path -LiteralPath $Bmp)) { throw ("Missing " + $Bmp) }

$fs = [System.IO.File]::OpenRead($Bmp)
try {
    $bytes = New-Object byte[] $fs.Length
    $null = $fs.Read($bytes, 0, $bytes.Length)
} finally { $fs.Close() }
$w = [BitConverter]::ToInt32($bytes, 18)
$h = [BitConverter]::ToInt32($bytes, 22)
$bpp = [BitConverter]::ToUInt16($bytes, 28)
$off = [BitConverter]::ToInt32($bytes, 10)
if ($bpp -ne 32) { throw ("orb_bg.bmp is " + $bpp + "bpp, want 32") }
Write-Host ("orb_bg.bmp: {0}x{1} data@{2}" -f $w, $h, $off)

$orbBmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
for ($y = 0; $y -lt $h; $y++) {
    $srcRow = $off + ($h - 1 - $y) * $w * 4
    for ($x = 0; $x -lt $w; $x++) {
        $o = $srcRow + $x * 4
        $a = $bytes[$o + 3]
        if ($a -eq 0) { $r = 0; $g = 0; $b = 0 }
        elseif ($a -eq 255) { $b = $bytes[$o]; $g = $bytes[$o + 1]; $r = $bytes[$o + 2] }
        else {
            $half = $a / 2
            $b = [Math]::Min(255, [int](($bytes[$o] * 255 + $half) / $a))
            $g = [Math]::Min(255, [int](($bytes[$o + 1] * 255 + $half) / $a))
            $r = [Math]::Min(255, [int](($bytes[$o + 2] * 255 + $half) / $a))
        }
        $orbBmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($a, $r, $g, $b))
    }
}
$orbBmp.Save($OutPng, [System.Drawing.Imaging.ImageFormat]::Png)
$orbBmp.Dispose()
Write-Host ("Wrote " + $OutPng)

# --- candidate: decode tools/orb-bow-master.bgra (fresh ingest) to a
# --- preview-only PNG. Never touches Files/Icons (that is the deploy step,
# --- done only after the user approves this preview).
$Master = Join-Path $PSScriptRoot 'orb-bow-master.bgra'
$CandPng = Join-Path $PSScriptRoot 'orb-candidate-72.png'
if (-not (Test-Path -LiteralPath $Master)) { throw ("Missing " + $Master) }
$raw = [System.IO.File]::ReadAllBytes($Master)
$M2 = [int][Math]::Sqrt($raw.Length / 4)
if ($M2 * $M2 * 4 -ne $raw.Length) { throw ("orb-bow-master.bgra bad size: " + $raw.Length) }
$cand = New-Object System.Drawing.Bitmap($M2, $M2, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
for ($y = 0; $y -lt $M2; $y++) {
    for ($x = 0; $x -lt $M2; $x++) {
        $o = ($y * $M2 + $x) * 4
        $a = $raw[$o + 3]
        if ($a -eq 0) { $r = 0; $g = 0; $b = 0 }
        elseif ($a -eq 255) { $b = $raw[$o]; $g = $raw[$o + 1]; $r = $raw[$o + 2] }
        else {
            $half = $a / 2
            $b = [Math]::Min(255, [int](($raw[$o] * 255 + $half) / $a))
            $g = [Math]::Min(255, [int](($raw[$o + 1] * 255 + $half) / $a))
            $r = [Math]::Min(255, [int](($raw[$o + 2] * 255 + $half) / $a))
        }
        $cand.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($a, $r, $g, $b))
    }
}
$cand.Save($CandPng, [System.Drawing.Imaging.ImageFormat]::Png)
$cand.Dispose()
Write-Host ("Wrote " + $CandPng + " (" + $M2 + "x" + $M2 + " from master)")

# Idempotent stamp: rewrite the ASCII-hook spans (re-runs keep updating).
$enc = New-Object System.Text.UTF8Encoding($false)
$html = [System.IO.File]::ReadAllText($OutHtml, $enc)
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
$bmpItem = Get-Item -LiteralPath $Bmp
$masterItem = Get-Item -LiteralPath $Master
$bmpInfo = "$($bmpItem.Length) bytes, " + $bmpItem.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
$masterInfo = "$($masterItem.Length) bytes, " + $masterItem.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
$html = [regex]::Replace($html, '(<span id="bmpinfo">)[^<]*(</span>)', ('${1}' + $bmpInfo + '${2}'))
$html = [regex]::Replace($html, '(<span id="masterinfo">)[^<]*(</span>)', ('${1}' + $masterInfo + '${2}'))
$html = [regex]::Replace($html, '(<span id="pagestamp">)[^<]*(</span>)', ('${1}page built ' + $stamp + '${2}'))
[System.IO.File]::WriteAllText($OutHtml, $html, $enc)
Write-Host ("Stamped " + $OutHtml)
if ($masterItem.LastWriteTime -gt $bmpItem.LastWriteTime) {
    Write-Host "NOTE: master is NEWER than orb_bg.bmp - regen via tools/deploy.ps1 after preview approval."
}

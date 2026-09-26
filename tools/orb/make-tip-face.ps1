<#
.SYNOPSIS
    Biotak Trigger TH3 - the hover chip's FACE master, ingested from the user's
    own calligraphy banner (P-UI-120).

    WHY IT IS INGESTED, NOT DRAWN. The user sent their plate twice: first one with
    religious lettering they wanted gone (that one was used for its PALETTE only,
    measured: navy #0F1322, gold #CFA77C, ember #9F2924), then this one - the
    Persian banner with the correct text - and said "put this one". So the art is
    the source of truth and this script only makes it fit for MT4: an MT4 bitmap
    label is CROPPED, never scaled, so the 1:1 master has to be baked at the final
    pixel size here (P-DRAW-33).

    THE ONE REAL TRAP: the PNG has NO alpha channel. Measured 2026-09-25 - every
    pixel is A=255 and the "transparency" is a PAINTED checkerboard (the corner
    reads R251 G252 B252), so the banner would ship as a square of chess squares.
    The checkerboard is therefore keyed out by its own signature (bright AND
    desaturated) and the keyed pixels are zeroed in RGB as well: GDI+ interpolates a
    rescale in premultiplied space, so leaving white RGB under alpha 0 would bleed a
    pale halo around every edge.

    Output: tools/orb/tip-face-master.bgra - premultiplied, top-down BGRA, which is
    what tools/gen-th3-icons.js embeds into Files/Icons/tip_face.bmp on every regen.

    NOTE: keep this file ASCII-only. PowerShell 5.1 decodes a BOM-less .ps1 as
    ANSI, so a UTF-8 em-dash becomes a smart quote and breaks the parser.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\orb\make-tip-face.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\orb\make-tip-face.ps1 -FaceW 168
#>
[CmdletBinding()]
param(
    [string]$Art = '',            # '' = tip-face-src.png beside this script
    [int]$FaceW = 200,            # the baked face's width in px; the height follows the art
    [int]$KeyMin = 210,           # checkerboard key: every channel must be >= this
    [int]$KeySpread = 14,         # ... and the channel spread this small (desaturated)
    [string]$OutMaster = ''       # '' = tip-face-master.bgra beside this script
)

# Every failure must STOP the bake (a non-terminating error once wrote a master
# while the script's own self-check had silently not run, measured 2026-09-25).
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing
if ([string]::IsNullOrEmpty($Art))       { $Art = Join-Path $PSScriptRoot 'tip-face-src.png' }
if ([string]::IsNullOrEmpty($OutMaster)) { $OutMaster = Join-Path $PSScriptRoot 'tip-face-master.bgra' }
if (-not (Test-Path $Art)) { throw "missing source art: $Art" }

# ---------------------------------------------------------------- 1) key the checkerboard
# LockBits + Marshal.Copy, never GetPixel: this is a 1.5 Mpx loop and GetPixel costs
# a COM call per pixel (the difference is minutes against seconds).
$src = New-Object System.Drawing.Bitmap -ArgumentList (Resolve-Path $Art).Path
$W = $src.Width; $H = $src.Height
$rect = New-Object System.Drawing.Rectangle(0, 0, $W, $H)
$data = $src.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$stride = $data.Stride
$px = New-Object byte[] ($stride * $H)
[System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $px, 0, $px.Length)
$src.UnlockBits($data)

$keyed = 0; $kept = 0
$minX = $W; $maxX = -1; $minY = $H; $maxY = -1
for ($y = 0; $y -lt $H; $y++) {
    $row = $y * $stride
    for ($x = 0; $x -lt $W; $x++) {
        $i = $row + $x * 4
        $b = $px[$i]; $g = $px[$i + 1]; $r = $px[$i + 2]
        $mx = [Math]::Max($r, [Math]::Max($g, $b))
        $mn = [Math]::Min($r, [Math]::Min($g, $b))
        if ($mn -ge $KeyMin -and ($mx - $mn) -le $KeySpread) {
            $px[$i] = 0; $px[$i + 1] = 0; $px[$i + 2] = 0; $px[$i + 3] = 0   # keyed: no RGB under alpha 0
            $keyed++
            continue
        }
        $px[$i + 3] = 255
        $kept++
        if ($x -lt $minX) { $minX = $x }
        if ($x -gt $maxX) { $maxX = $x }
        if ($y -lt $minY) { $minY = $y }
        if ($y -gt $maxY) { $maxY = $y }
    }
}
if ($kept -le 0) { throw 'the key removed everything: the art is not what this script expects' }
Write-Host ("source: {0}x{1}; keyed {2} checkerboard px, kept {3} art px (key: R,G,B >= {4} and spread <= {5})" -f $W, $H, $keyed, $kept, $KeyMin, $KeySpread)

$masked = New-Object System.Drawing.Bitmap($W, $H, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$md = $masked.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
[System.Runtime.InteropServices.Marshal]::Copy($px, 0, $md.Scan0, $px.Length)
$masked.UnlockBits($md)

# ---------------------------------------------------------------- 2) crop, then resize
$bw = $maxX - $minX + 1
$bh = $maxY - $minY + 1
if ($FaceW -lt 24 -or $FaceW -gt 600) { throw "FaceW $FaceW is outside the sane band" }
$FH = [int][Math]::Round($FaceW * $bh / [double]$bw)

# premultiplied DEST on purpose: GDI+ writes the resampled result already in the
# master's own format, so the alpha stays honest at every edge pixel.
$face = New-Object System.Drawing.Bitmap($FaceW, $FH, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
$fg = [System.Drawing.Graphics]::FromImage($face)
$fg.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
$fg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$fg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$fg.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
$fg.DrawImage($masked, (New-Object System.Drawing.Rectangle(0, 0, $FaceW, $FH)),
              (New-Object System.Drawing.Rectangle($minX, $minY, $bw, $bh)), [System.Drawing.GraphicsUnit]::Pixel)
$fg.Dispose()

# ---------------------------------------------------------------- 3) read + self-check
$fr = New-Object System.Drawing.Rectangle(0, 0, $FaceW, $FH)
$fd = $face.LockBits($fr, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
$fstride = $fd.Stride
$out = New-Object byte[] ($fstride * $FH)
[System.Runtime.InteropServices.Marshal]::Copy($fd.Scan0, $out, 0, $out.Length)
$face.UnlockBits($fd)
$face.Dispose(); $masked.Dispose(); $src.Dispose()

# Repack to a tight stride (the master is W*H*4 with no padding).
$tight = New-Object byte[] ($FaceW * $FH * 4)
for ($y = 0; $y -lt $FH; $y++) {
    [Array]::Copy($out, $y * $fstride, $tight, $y * $FaceW * 4, $FaceW * 4)
}

# A face must be MOSTLY OPAQUE with a see-through surround: the two failures worth
# gating are a chess square that survived (coverage ~100 % in the corners) and a
# key that ate the art (nothing opaque at all).
$opq = 0; $soft = 0; $clr = 0
for ($i = 3; $i -lt $tight.Length; $i += 4) {
    $a = $tight[$i]
    if ($a -ge 250) { $opq++ } elseif ($a -le 6) { $clr++ } else { $soft++ }
}
# EVERY product is parenthesised on purpose: in PowerShell the comma of an array
# literal binds TIGHTER than '*', so `@(0, ($W - 1) * 4)` is really `@((0, ($W-1)) * 4)`.
$corners = @((0), ((($FaceW - 1) * 4)), (((($FH - 1) * $FaceW) * 4)), (((($FaceW * $FH) - 1) * 4)))
foreach ($oo in $corners) {
    if ($tight[$oo + 3] -gt 8) { throw ('a corner is opaque (alpha ' + $tight[$oo + 3] + '): the checkerboard key missed') }
}
$coverage = 100.0 * $opq / ($FaceW * $FH)
if ($coverage -lt 25.0) { throw ('only ' + [int]$coverage + ' % of the face is opaque: the key ate the art') }
Write-Host ("tip face: {0}x{1} px from a {2}x{3} art bbox; opaque {4} / soft {5} / clear {6} px = {7} % solid" -f $FaceW, $FH, $bw, $bh, $opq, $soft, $clr, [int]$coverage)
Write-Host ("tip face self-check: 4 corners transparent, coverage over the floor, source PNG '{0}'" -f (Split-Path $Art -Leaf))

[System.IO.File]::WriteAllBytes($OutMaster, $tight)
Write-Host "Wrote $OutMaster ($($tight.Length) bytes premultiplied BGRA)"
Write-Host "Next: node tools/gen-th3-icons.js  (embeds it into Files/Icons/tip_face.bmp)"
Write-Host ("The MQL side sizes the face object from CIRC_TIP_FACE_W/H - set them to {0}/{1}." -f $FaceW, $FH)

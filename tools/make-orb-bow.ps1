<#
.SYNOPSIS
    Biotak Trigger TH3 — bow-medallion orb master builder (one-time art ingest).

    Takes an opaque bow-medallion render (e.g. Desktop\trigger.png, 1024x1024
    with a baked checkerboard "transparency" background) and produces:
      1. tools/orb-bow-clean.png  — 256x256 straight-alpha RGBA, checkerboard
         removed via a feathered circular mask fitted to the gold ring.
      2. tools/orb-bow-master.bgra — MxM top-down (default 72x72)
         PREMULTIPLIED BGRA bytes,
         the single source of truth that tools/gen-th3-icons.js embeds into
         Files/Icons/orb_bg.bmp on every regen (see P-ICONS-04 in AGENTS.md).

    The checkerboard is detected (not assumed): pixels with low saturation in
    the mid-gray band are "checker". The medallion edge is found by scanning
    the middle row/column inward from each side, so the mask auto-fits the
    artwork instead of relying on hard-coded geometry.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-orb-bow.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-orb-bow.ps1 -Source 'D:\art\bow.png'
#> 
#  P-ICONS-05: the orb renders at 64px on-chart (72px canvas incl. margin),
#  so the default master is 72 (was 56). Lift raises the dark galaxy
#  interior slightly so the medallion reads on black charts.
[CmdletBinding()]
param(
    [string]$Source = (Join-Path $env:USERPROFILE 'Desktop\trigger.png'),
    [int]$MasterSize = 72,
    [double]$Lift = 0.06,
    [double]$SatBoost = 1.45,    # gold saturation rescue at 256px (1.0 = off)
    [double]$Sharpen = 0.9,       # unsharp amount at MASTER scale (0 = off)
    [double]$CropPad = 1.45,      # SOURCE-region selector only: crop half-width as a
                                  # multiple of medallion radius. WARNING: the crop
                                  # clamps to the image bounds, so for tight cut-out
                                  # sources this is a silent no-op (see P-ICONS-07).
                                  # Real visual size = $OrbFill below.
    [double]$OrbFill = 0.86       # FINAL visual size: medallion diameter as a fraction
                                  # of the canvas (0.86 = ~62px on the 72px canvas,
                                  # 2026-09-04).
                                  # Applied AFTER resampling (P-ICONS-07).
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$Root   = Split-Path -Parent $PSScriptRoot
$CleanP = Join-Path $PSScriptRoot 'orb-bow-clean.png'
$Master = Join-Path $PSScriptRoot 'orb-bow-master.bgra'

# Rolling backup of previous outputs (single .prev generation, overwritten
# each run — never lose the last good master, never accumulate files).
if (Test-Path -LiteralPath $CleanP) { Copy-Item -LiteralPath $CleanP -Destination ($CleanP + '.prev') -Force }
if (Test-Path -LiteralPath $Master) { Copy-Item -LiteralPath $Master -Destination ($Master + '.prev') -Force }

if (-not (Test-Path -LiteralPath $Source)) { throw "Source image not found: $Source" }

function Test-Checker([System.Drawing.Color]$c) {
    # DARK checkerboard (AI-generator transparency preview): near-black squares
    # (v<25) alternating with dark-gray squares (v 60..95), both desaturated.
    # LIGHT checkerboard (newer generators): near-white desaturated squares
    # (v>=235). Soft 2-4px transitions between squares are NOT checker.
    $mx = [Math]::Max($c.R, [Math]::Max($c.G, $c.B))
    $mn = [Math]::Min($c.R, [Math]::Min($c.G, $c.B))
    if (($mx - $mn) -ge 30) { return $false }
    return ($mx -lt 25 -or ($mx -ge 60 -and $mx -le 95) -or $mx -ge 235)
}

function Find-Edge($src, $W, $H, $fixed, $isRow, $fromStart) {
    # Scan one line; ignore short (<6px) non-checker runs (square transitions,
    # sparkles, viewer labels). Returns the edge pixel index.
    if ($isRow) { $len = $W } else { $len = $H }
    $run = 0
    for ($i = 0; $i -lt $len; $i++) {
        if ($fromStart) { $p = $i } else { $p = $len - 1 - $i }
        if ($isRow) { $c = $src.GetPixel($p, $fixed) } else { $c = $src.GetPixel($fixed, $p) }
        if (Test-Checker $c) { $run = 0; continue }
        $run += 1   # NOTE: never $run++ here — PowerShell emits ++ as output, turning the return into an array
        if ($run -ge 6) { if ($fromStart) { return ($p - 5) } else { return ($p + 5) } }
    }
    if ($fromStart) { return 0 } else { return ($len - 1) }
}

function Get-Median($arr) {
    $s = @($arr | Sort-Object); return $s[[int]($s.Count / 2)]
}

function Test-HasRealAlpha($src, $W, $H) {
    # Transparent-source detector: true when the artwork already carries a
    # real alpha channel (e.g. remove.bg cut-out BMP/PNG) instead of a baked
    # checkerboard. Corners transparent + center opaque = use alpha path.
    $c0 = $src.GetPixel(0, 0)
    $c1 = $src.GetPixel($W - 1, 0)
    $c2 = $src.GetPixel(0, $H - 1)
    $c3 = $src.GetPixel($W - 1, $H - 1)
    $cc = $src.GetPixel([int]($W / 2), [int]($H / 2))
    $cornerA = ($c0.A + $c1.A + $c2.A + $c3.A) / 4.0
    return ($cornerA -lt 10 -and $cc.A -gt 200)
}

function Find-AlphaExtent($src, $W, $H) {
    # Bounding box of pixels with A>10 on a coarse grid, refined on the
    # middle row/column. Returns @(cx, cy, r).
    $step = 3
    $minX = $W; $maxX = -1; $minY = $H; $maxY = -1
    for ($y = 0; $y -lt $H; $y += $step) {
        for ($x = 0; $x -lt $W; $x += $step) {
            if ($src.GetPixel($x, $y).A -gt 10) {
                if ($x -lt $minX) { $minX = $x }
                if ($x -gt $maxX) { $maxX = $x }
                if ($y -lt $minY) { $minY = $y }
                if ($y -gt $maxY) { $maxY = $y }
            }
        }
    }
    if ($maxX -lt 0) { throw 'Find-AlphaExtent: no opaque pixels found' }
    $cx = ($minX + $maxX) / 2.0
    $cy = ($minY + $maxY) / 2.0
    $r = ((($maxX - $minX) + ($maxY - $minY)) / 2.0) / 2.0
    return @($cx, $cy, $r)
}

function Build-OrbPixelsAlpha($srcBmp, $cropRect, $M, $liftV, $satV) {
    # Alpha-preserving resample for transparent sources (remove.bg cut-outs):
    # GDI+ bicubic keeps the source alpha — NO circular mask override, so the
    # artist's own feathered edge survives. Sat/Lift touch RGB only.
    # Returns straight-alpha RGBA bytes (top-down, stride-safe).
    $bmp = New-Object System.Drawing.Bitmap($M, $M, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gg = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $gg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $gg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $dstRect = New-Object System.Drawing.Rectangle(0, 0, $M, $M)
        $gg.DrawImage($srcBmp, $dstRect, $cropRect, [System.Drawing.GraphicsUnit]::Pixel)
    } finally { $gg.Dispose() }
    $rect = New-Object System.Drawing.Rectangle(0, 0, $M, $M)
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadWrite,
                          [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $stride = $data.Stride
        $n = $stride * $M
        $px = New-Object byte[] $n
        [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $px, 0, $n)
        for ($yy = 0; $yy -lt $M; $yy += 1) {
            $row = $yy * $stride
            for ($xx = 0; $xx -lt $M; $xx += 1) {
                $oo = $row + $xx * 4
                $aa = [int]$px[$oo + 3]
                if ($aa -eq 0) { continue }
                if ($satV -gt 1.0) {
                    $b0 = [int]$px[$oo]; $g0 = [int]$px[$oo + 1]; $r0 = [int]$px[$oo + 2]
                    $mx0 = [Math]::Max($r0, [Math]::Max($g0, $b0))
                    $mn0 = [Math]::Min($r0, [Math]::Min($g0, $b0))
                    $sat0 = $mx0 - $mn0
                    if ($sat0 -gt 12) {
                        $mean0 = ($r0 + $g0 + $b0) / 3.0
                        $kk = 1.0 + ($satV - 1.0) * [Math]::Min(1.0, $sat0 / 80.0)
                        $rn = [int][Math]::Min(255, [Math]::Max(0, $mean0 + ($r0 - $mean0) * $kk))
                        $gn = [int][Math]::Min(255, [Math]::Max(0, $mean0 + ($g0 - $mean0) * $kk))
                        $bn = [int][Math]::Min(255, [Math]::Max(0, $mean0 + ($b0 - $mean0) * $kk))
                        $px[$oo] = [byte]$bn; $px[$oo + 1] = [byte]$gn; $px[$oo + 2] = [byte]$rn
                    }
                }
                $px[$oo]     = [byte]($px[$oo]     + (255 - $px[$oo])     * $liftV)
                $px[$oo + 1] = [byte]($px[$oo + 1] + (255 - $px[$oo + 1]) * $liftV)
                $px[$oo + 2] = [byte]($px[$oo + 2] + (255 - $px[$oo + 2]) * $liftV)
            }
        }
        [System.Runtime.InteropServices.Marshal]::Copy($px, 0, $data.Scan0, $n)
    } finally { $bmp.UnlockBits($data) }
    $out = New-Object byte[] ($M * $M * 4)
    $rect2 = New-Object System.Drawing.Rectangle(0, 0, $M, $M)
    $data2 = $bmp.LockBits($rect2, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                           [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $stride2 = $data2.Stride
        $tmp = New-Object byte[] ($stride2 * $M)
        [System.Runtime.InteropServices.Marshal]::Copy($data2.Scan0, $tmp, 0, $tmp.Length)
        for ($yy = 0; $yy -lt $M; $yy += 1) {
            [Array]::Copy($tmp, ($yy * $stride2), $out, ($yy * $M * 4), ($M * 4))
        }
    } finally { $bmp.UnlockBits($data2); $bmp.Dispose() }
    return ,$out
}

function Build-OrbPixels($srcBmp, $cropRect, $M, $fitCx, $fitCy, $fitR, $liftV, $satV) {
    # Single-step high-quality resample: source crop -> MxM straight-alpha RGBA.
    # Returns a byte[] (top-down, R/G/B straight, A applied from feathered mask).
    # Indexing is stride-safe (uses the locked stride, never assumes width*4).
    $bmp = New-Object System.Drawing.Bitmap($M, $M, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gg = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $gg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $gg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $dstRect = New-Object System.Drawing.Rectangle(0, 0, $M, $M)
        $gg.DrawImage($srcBmp, $dstRect, $cropRect, [System.Drawing.GraphicsUnit]::Pixel)
    } finally { $gg.Dispose() }
    $wcx = ($fitCx - $cropRect.X) * $M / [double]$cropRect.Width
    $wcy = ($fitCy - $cropRect.Y) * $M / [double]$cropRect.Height
    $wr = $fitR * $M / [double]$cropRect.Width
    $mR0 = $wr
    $mR1 = $wr + $wr * 0.022
    $rect = New-Object System.Drawing.Rectangle(0, 0, $M, $M)
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadWrite,
                          [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $stride = $data.Stride
        $n = $stride * $M
        $px = New-Object byte[] $n
        [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $px, 0, $n)
        for ($yy = 0; $yy -lt $M; $yy += 1) {
            $dyy = ($yy + 0.5) - $wcy
            $row = $yy * $stride
            for ($xx = 0; $xx -lt $M; $xx += 1) {
                $dxx = ($xx + 0.5) - $wcx
                $dd = [Math]::Sqrt($dxx * $dxx + $dyy * $dyy)
                if ($dd -le $mR0) { $aa = 255 }
                elseif ($dd -ge $mR1) { $aa = 0 }
                else {
                    $tt = ($dd - $mR0) / ($mR1 - $mR0)
                    $aa = 255 - [int](255 * ($tt * $tt * (3 - 2 * $tt)))
                }
                $oo = $row + $xx * 4
                if ($satV -gt 1.0) {
                    $b0 = [int]$px[$oo]; $g0 = [int]$px[$oo + 1]; $r0 = [int]$px[$oo + 2]
                    $mx0 = [Math]::Max($r0, [Math]::Max($g0, $b0))
                    $mn0 = [Math]::Min($r0, [Math]::Min($g0, $b0))
                    $sat0 = $mx0 - $mn0
                    if ($sat0 -gt 12) {
                        $mean0 = ($r0 + $g0 + $b0) / 3.0
                        $kk = 1.0 + ($satV - 1.0) * [Math]::Min(1.0, $sat0 / 80.0)
                        $rn = [int][Math]::Min(255, [Math]::Max(0, $mean0 + ($r0 - $mean0) * $kk))
                        $gn = [int][Math]::Min(255, [Math]::Max(0, $mean0 + ($g0 - $mean0) * $kk))
                        $bn = [int][Math]::Min(255, [Math]::Max(0, $mean0 + ($b0 - $mean0) * $kk))
                        $px[$oo] = [byte]$bn; $px[$oo + 1] = [byte]$gn; $px[$oo + 2] = [byte]$rn
                    }
                }
                $px[$oo]     = [byte]($px[$oo]     + (255 - $px[$oo])     * $liftV)
                $px[$oo + 1] = [byte]($px[$oo + 1] + (255 - $px[$oo + 1]) * $liftV)
                $px[$oo + 2] = [byte]($px[$oo + 2] + (255 - $px[$oo + 2]) * $liftV)
                $px[$oo + 3] = [byte]$aa
            }
        }
        [System.Runtime.InteropServices.Marshal]::Copy($px, 0, $data.Scan0, $n)
    } finally { $bmp.UnlockBits($data) }
    # flatten to tight top-down straight RGBA (drop stride padding, if any)
    $out = New-Object byte[] ($M * $M * 4)
    $rect2 = New-Object System.Drawing.Rectangle(0, 0, $M, $M)
    $data2 = $bmp.LockBits($rect2, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                           [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $stride2 = $data2.Stride
        $tmp = New-Object byte[] ($stride2 * $M)
        [System.Runtime.InteropServices.Marshal]::Copy($data2.Scan0, $tmp, 0, $tmp.Length)
        for ($yy = 0; $yy -lt $M; $yy += 1) {
            [Array]::Copy($tmp, ($yy * $stride2), $out, ($yy * $M * 4), ($M * 4))
        }
    } finally { $bmp.UnlockBits($data2); $bmp.Dispose() }
    return ,$out
}

function Resize-OrbToFill($rgba, $M, $fill) {
    # Final visual-size control (P-ICONS-07): composites the MxM art scaled to
    # fill*M px, centered on a transparent MxM canvas (GDI+ bicubic keeps the
    # alpha edge). Returns straight-alpha RGBA bytes, stride-safe.
    if ($fill -ge 0.999) { return ,$rgba }
    $d = $fill * $M
    $off = ($M - $d) / 2.0
    $srcBmp = New-Object System.Drawing.Bitmap($M, $M, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        for ($yy = 0; $yy -lt $M; $yy += 1) {
            for ($xx = 0; $xx -lt $M; $xx += 1) {
                $oo = ($yy * $M + $xx) * 4
                $c = [System.Drawing.Color]::FromArgb($rgba[$oo + 3], $rgba[$oo + 2], $rgba[$oo + 1], $rgba[$oo])
                $srcBmp.SetPixel($xx, $yy, $c)
            }
        }
        $dst = New-Object System.Drawing.Bitmap($M, $M, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $gg = [System.Drawing.Graphics]::FromImage($dst)
            try {
                $gg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $gg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $dstRect = New-Object System.Drawing.RectangleF($off, $off, $d, $d)
                $gg.DrawImage($srcBmp, $dstRect)
            } finally { $gg.Dispose() }
            $rect = New-Object System.Drawing.Rectangle(0, 0, $M, $M)
            $data = $dst.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                                  [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            try {
                $stride = $data.Stride
                $tmp = New-Object byte[] ($stride * $M)
                [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $tmp, 0, $tmp.Length)
                $out = New-Object byte[] ($M * $M * 4)
                for ($yy = 0; $yy -lt $M; $yy += 1) {
                    [Array]::Copy($tmp, ($yy * $stride), $out, ($yy * $M * 4), ($M * 4))
                }
            } finally { $dst.UnlockBits($data) }
        } finally { $dst.Dispose() }
    } finally { $srcBmp.Dispose() }
    return ,$out
}

function Save-StraightPng($rgba, $M, $path) {
    $bmp = New-Object System.Drawing.Bitmap($M, $M, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        for ($yy = 0; $yy -lt $M; $yy += 1) {
            for ($xx = 0; $xx -lt $M; $xx += 1) {
                $oo = ($yy * $M + $xx) * 4
                $c = [System.Drawing.Color]::FromArgb($rgba[$oo + 3], $rgba[$oo + 2], $rgba[$oo + 1], $rgba[$oo])
                $bmp.SetPixel($xx, $yy, $c)
            }
        }
        $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $bmp.Dispose() }
}

function Test-OrbDisc($rgba, $M, $what) {
    # Self-check: corners must be transparent, center must be opaque.
    # Never ship a white square again.
    $chan = 3
    $corners = @(0, (($M - 1) * 4), ((($M - 1) * $M) * 4), ((($M * $M - 1)) * 4))
    foreach ($oo in $corners) {
        if ($rgba[$oo + $chan] -gt 127) { throw ("{0}: corner still opaque, mask failed" -f $what) }
    }
    $mid = (([int]($M / 2) * $M + [int]($M / 2)) * 4)
    if ($rgba[$mid + $chan] -lt 200) { throw ("{0}: center transparent, mask failed" -f $what) }
    Write-Host ("{0}: disc check OK (corners transparent, center opaque)" -f $what)
}

$src = [System.Drawing.Bitmap]::FromFile($Source)
try {
    $W = $src.Width; $H = $src.Height
    Write-Host "Source: ${W}x${H}  $Source"

    $script:UseAlpha = Test-HasRealAlpha $src $W $H
    if ($script:UseAlpha) {
        Write-Host 'Source has real alpha (cut-out) — using alpha-preserving path.'
        $ext = Find-AlphaExtent $src $W $H
        $cx = $ext[0]; $cy = $ext[1]; $rDet = $ext[2]
        Write-Host ("Alpha fit: center=({0:0},{1:0}) r={2:0}" -f $cx, $cy, $rDet)
    } else {
    # --- fit the medallion: scan 3 rows / 3 columns from each side, median ---
    # NOTE (PS 5.1 quirk): never put -/+ arithmetic inside a multi-element @()
    # literal — e.g. @($H - $off, $H) misparses and throws op_Subtraction on
    # Object[]. Always precompute into temp scalars first (see P-TOOL-02).
    $off = [int]($H * 0.04)
    $halfH = [int]($H / 2)
    $rLo = $halfH - $off
    $rHi = $halfH + $off
    $rows = @($rLo, $halfH, $rHi)
    $Ls = @(); $Rs = @()
    foreach ($yy in $rows) {
        $le = Find-Edge $src $W $H $yy $true $true
        $Ls += $le
        $ri = Find-Edge $src $W $H $yy $true $false
        $Rs += $ri
    }
    $L = Get-Median $Ls; $R = Get-Median $Rs
    $cx = ($L + $R) / 2.0; $rx = ($R - $L) / 2.0

    $midX = [int][Math]::Max(0, [Math]::Min($W - 1, $cx))
    $Ts = @(); $Bs = @()
    $cLo = $midX - $off
    $cHi = $midX + $off
    $cols = @($cLo, $midX, $cHi)
    foreach ($xx in $cols) {
        $x2 = [int][Math]::Max(0, [Math]::Min($W - 1, $xx))
        $Ts += Find-Edge $src $W $H $x2 $false $true
        $Bs += Find-Edge $src $W $H $x2 $false $false
    }
    $T = Get-Median $Ts; $B = Get-Median $Bs
    $cy = ($T + $B) / 2.0; $ry = ($B - $T) / 2.0

    $rDet = ($rx + $ry) / 2.0
    if ($rDet -lt $W * 0.30 -or $rDet -gt $W * 0.52) {
        Write-Warning "Edge detection looks off (r=$rDet) - falling back to centered geometry."
        $cx = $W / 2.0; $cy = $H / 2.0; $rDet = $W * 0.42
    }
    Write-Host ("Medallion fit: center=({0:0},{1:0}) r={2:0}" -f $cx, $cy, $rDet)
    }

    # --- centered square crop (ring + halo + small margin), clamped to bounds ---
    $half = $rDet * $CropPad
    $side = [int](2 * $half)
    if ($side -gt $W) { $side = $W }; if ($side -gt $H) { $side = $H }
    $x0 = [int]([Math]::Max(0, [Math]::Min($W - $side, $cx - $half)))
    $y0 = [int]([Math]::Max(0, [Math]::Min($H - $side, $cy - $half)))
    $crop = New-Object System.Drawing.Rectangle($x0, $y0, $side, $side)

    # --- clean 256: single-step resample straight from the source crop ---
    $S = 256
    if ($script:UseAlpha) {
        $cleanRgba = Build-OrbPixelsAlpha $src $crop $S $Lift $SatBoost
    } else {
        $cleanRgba = Build-OrbPixels $src $crop $S $cx $cy $rDet $Lift $SatBoost
    }
    $cleanRgba = Resize-OrbToFill $cleanRgba $S $OrbFill
    Test-OrbDisc $cleanRgba $S 'clean 256'
    Save-StraightPng $cleanRgba $S $CleanP
    Write-Host "Wrote $CleanP (256x256 straight-alpha)"
} finally { $src.Dispose() }

# --- master: single-step resample straight from the source crop (NOT via
# --- the 256 intermediate - one bicubic step keeps the engraving sharp),
# --- then unsharp at master scale, then premultiply into the raw master ---
$M = $MasterSize
$src2 = [System.Drawing.Bitmap]::FromFile($Source)
try {
    if ($script:UseAlpha) {
        $mRgba = Build-OrbPixelsAlpha $src2 $crop $M $Lift $SatBoost
    } else {
        $mRgba = Build-OrbPixels $src2 $crop $M $cx $cy $rDet $Lift $SatBoost
    }
    $mRgba = Resize-OrbToFill $mRgba $M $OrbFill
    Test-OrbDisc $mRgba $M 'master'
    $raw = $mRgba
    $n2 = $raw.Length
    if ($Sharpen -gt 0.0) {
            # unsharp mask at MASTER scale: this is the size the chart actually
            # shows, so restoring edge bite HERE is what makes the engraving
            # pop at 64px (sharpening only at 256px gets averaged away again).
            # 3x3 binomial blur approx, straight-alpha RGB (alpha untouched).
            $srcP = New-Object byte[] $n2
            [Array]::Copy($raw, $srcP, $n2)
            for ($y = 0; $y -lt $M; $y++) {
                $ya = $y - 1; if ($ya -lt 0) { $ya = 0 }
                $yc = $y + 1; if ($yc -gt $M - 1) { $yc = $M - 1 }
                for ($x = 0; $x -lt $M; $x++) {
                    $xa = $x - 1; if ($xa -lt 0) { $xa = 0 }
                    $xc = $x + 1; if ($xc -gt $M - 1) { $xc = $M - 1 }
                    $oa = ($y * $M + $x) * 4
                    $r00 = ($ya * $M + $xa) * 4; $r10 = ($ya * $M + $x) * 4; $r20 = ($ya * $M + $xc) * 4
                    $r01 = ($y * $M + $xa) * 4;                                           $r21 = ($y * $M + $xc) * 4
                    $r02 = ($yc * $M + $xa) * 4; $r12 = ($yc * $M + $x) * 4; $r22 = ($yc * $M + $xc) * 4
                    for ($ch = 0; $ch -lt 3; $ch++) {
                        $sum = [int]$srcP[$r00 + $ch] + 2 * [int]$srcP[$r10 + $ch] + [int]$srcP[$r20 + $ch] +
                               2 * [int]$srcP[$r01 + $ch] + 4 * [int]$srcP[$oa + $ch] + 2 * [int]$srcP[$r21 + $ch] +
                               [int]$srcP[$r02 + $ch] + 2 * [int]$srcP[$r12 + $ch] + [int]$srcP[$r22 + $ch]
                        $blurV = [int]($sum / 16)
                        $v = [int]$srcP[$oa + $ch] + [int](($srcP[$oa + $ch] - $blurV) * $Sharpen)
                        if ($v -lt 0) { $v = 0 }
                        if ($v -gt 255) { $v = 255 }
                        $raw[$oa + $ch] = [byte]$v
                    }
                }
            }
        }
        for ($i = 0; $i -lt $n2; $i += 4) {
            $a = $raw[$i + 3]
            if ($a -eq 255) { continue }
            if ($a -eq 0) { $raw[$i] = 0; $raw[$i + 1] = 0; $raw[$i + 2] = 0; continue }
            $raw[$i]     = [byte](($raw[$i]     * $a + 127) / 255)   # B
            $raw[$i + 1] = [byte](($raw[$i + 1] * $a + 127) / 255)   # G
            $raw[$i + 2] = [byte](($raw[$i + 2] * $a + 127) / 255)   # R
        }
        [System.IO.File]::WriteAllBytes($Master, $raw)
        Write-Host "Wrote $Master ($($raw.Length) bytes premultiplied BGRA)"
} finally { $src2.Dispose() }

Write-Host "Done. Next: node tools/gen-th3-icons.js  (embeds the master into Files/Icons/orb_bg.bmp)"

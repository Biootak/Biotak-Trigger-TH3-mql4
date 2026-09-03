#requires -Version 5.1
# Biotak premium icon set generator (v2, LEGACY — superseded 2026-09-03)
# DEPRECATED: see AGENTS.md R-ICONS / P-ICONS-02. Use: node tools/gen-th3-icons.js
# Output: 32-bit BGRA BMPs (matching what MQL4/MetaTrader expects)
# Targets: \Files\Icons\ (the active resource directory)
# Usage:   powershell -File gen-icons.ps1 -OutputDir "<target dir>"

[CmdletBinding()]
param(
    [string]$OutputDir
)

Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'
if ($PSBoundParameters.ContainsKey('OutputDir') -and $OutputDir) {
    $Dir = $OutputDir
} else {
    $Dir = Join-Path $PSScriptRoot '..\Files\Icons'
}
if (-not (Test-Path $Dir)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }

# ---------- palette ----------
$Gold      = [System.Drawing.Color]::FromArgb(255, 255, 178, 56)
$GoldHi    = [System.Drawing.Color]::FromArgb(255, 255, 224, 150)
$GoldDeep  = [System.Drawing.Color]::FromArgb(255, 216, 132, 24)
$Silver    = [System.Drawing.Color]::FromArgb(255, 198, 206, 220)
$SilverHi  = [System.Drawing.Color]::FromArgb(255, 232, 238, 248)
$SilverDim = [System.Drawing.Color]::FromArgb(255, 128, 136, 152)
$Ink       = [System.Drawing.Color]::FromArgb(255,  14,  18,  28)
$InkSoft   = [System.Drawing.Color]::FromArgb(255,  28,  34,  50)

function New-Bitmap([int]$w, [int]$h) {
    return New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
}

function Save-Bmp32([System.Drawing.Bitmap]$bmp, [string]$path) {
    $clone = New-Bitmap $bmp.Width $bmp.Height
    $g = [System.Drawing.Graphics]::FromImage($clone)
    $g.CompositingMode    = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.DrawImage($bmp, 0, 0)
    $g.Dispose()
    $bmp.Dispose()
    $clone.Save($path, [System.Drawing.Imaging.ImageFormat]::Bmp)
    $clone.Dispose()
}

function New-Gfx([System.Drawing.Bitmap]$bmp) {
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    return $g
}

function Pen([System.Drawing.Color]$c, [single]$w = 1.0) {
    return New-Object System.Drawing.Pen $c, $w
}

function Brush([System.Drawing.Color]$c) {
    return New-Object System.Drawing.SolidBrush $c
}

# Linear gradient pen across the full icon canvas (premium metallic stroke)
function GradPen([int]$canvas, [System.Drawing.Color]$c1, [System.Drawing.Color]$c2, [single]$w) {
    $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point 0, 0),
        (New-Object System.Drawing.Point $canvas, $canvas),
        $c1, $c2)
    $p = New-Object System.Drawing.Pen $lg, $w
    $lg.Dispose()
    return $p
}

function GradBrush([int]$x, [int]$y, [int]$w, [int]$h, [System.Drawing.Color]$c1, [System.Drawing.Color]$c2) {
    return New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point $x, $y),
        (New-Object System.Drawing.Point $x, ($y + $h)),
        $c1, $c2)
}

function State-Pen([bool]$on, [int]$canvas, [single]$w) {
    if ($on) { return GradPen $canvas $GoldHi $GoldDeep $w }
    return (Pen $SilverDim $w)
}

function State-Fill([bool]$on, [int]$x, [int]$y, [int]$w, [int]$h) {
    if ($on) { return GradBrush $x $y $w $h $GoldHi $GoldDeep }
    return (Brush $SilverDim)
}

function Add-RRect([System.Drawing.Drawing2D.GraphicsPath]$path, [single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $r = [Math]::Min($r, [Math]::Min($w, $h) / 2.0)
    $path.AddArc($x, $y, $r*2, $r*2, 180, 90)
    $path.AddArc($x + $w - $r*2, $y, $r*2, $r*2, 270, 90)
    $path.AddArc($x + $w - $r*2, $y + $h - $r*2, $r*2, $r*2, 0, 90)
    $path.AddArc($x, $y + $h - $r*2, $r*2, $r*2, 90, 90)
    $path.CloseFigure()
}

# Soft halo: redraws the silhouette stroke wide + translucent (premium glow)
function Draw-Halo([System.Drawing.Graphics]$g, [bool]$on, [scriptblock]$strokeSilhouette) {
    if (-not $on) { return }
    $halo = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(70, 255, 190, 80)), 4.0
    & $strokeSilhouette $g $halo
    $halo.Dispose()
}

# zone — Trigger Levels: band between two glowing level rails
function Draw-Zone([System.Drawing.Graphics]$g, [bool]$on) {
    $s = 28
    $halo = {
        param($gg, $p)
        $gg.DrawLine($p, 5, 6, 23, 6)
        $gg.DrawLine($p, 5, 22, 23, 22)
        $gg.DrawRectangle($p, 6.5, 10.5, 15, 7)
    }
    Draw-Halo $g $on $halo
    $rp = State-Pen $on $s 2.0
    $g.DrawLine($rp, 5, 6, 23, 6)
    $g.DrawLine($rp, 5, 22, 23, 22)
    $g.DrawLine((Pen ([System.Drawing.Color]::FromArgb(160, 128, 136, 152)) 1.0), 9, 6, 9, 22)
    $g.DrawLine((Pen ([System.Drawing.Color]::FromArgb(160, 128, 136, 152)) 1.0), 19, 6, 19, 22)
    $rp.Dispose()
    $band = New-Object System.Drawing.Drawing2D.GraphicsPath
    Add-RRect $band 6.5 10.5 15 7 3
    $bf = State-Fill $on 6 10 15 8
    $g.FillPath($bf, $band)
    $band.Dispose(); $bf.Dispose()
    if ($on) {
        $g.DrawLine((Pen ([System.Drawing.Color]::FromArgb(150, 255, 255, 255)) 1.0), 8, 11.5, 20, 11.5)
    }
}

# chk — Lines Visibility: eye
function Draw-Chk([System.Drawing.Graphics]$g, [bool]$on) {
    $s = 28
    $halo = {
        param($gg, $p)
        $q = New-Object System.Drawing.Drawing2D.GraphicsPath
        $q.AddBezier( 3, 14,  8,  6, 20,  6, 25, 14)
        $q.AddBezier(25, 14, 20, 22,  8, 22,  3, 14)
        $gg.DrawPath($p, $q)
        $q.Dispose()
    }
    Draw-Halo $g $on $halo
    if ($on) {
        $p = New-Object System.Drawing.Drawing2D.GraphicsPath
        $p.AddBezier( 3, 14,  8,  6, 20,  6, 25, 14)
        $p.AddBezier(25, 14, 20, 22,  8, 22,  3, 14)
        $f = GradBrush 3 6 22 16 $GoldHi $GoldDeep
        $g.FillPath($f, $p)
        $p.Dispose(); $f.Dispose()
        $g.FillEllipse((Brush $Ink), 10.5, 10.5, 7, 7)
        $iri = GradBrush 12 12 4 4 $GoldHi $Gold
        $g.FillEllipse($iri, 12, 12, 4, 4)
        $iri.Dispose()
        $g.FillEllipse((Brush ([System.Drawing.Color]::FromArgb(220, 255, 255, 255))), 12.7, 12.7, 1.6, 1.6)
    } else {
        $p = New-Object System.Drawing.Drawing2D.GraphicsPath
        $p.AddBezier( 3, 14,  8,  6, 20,  6, 25, 14)
        $p.AddBezier(25, 14, 20, 22,  8, 22,  3, 14)
        $g.DrawPath((Pen $SilverDim 1.8), $p)
        $p.Dispose()
        $g.FillEllipse((Brush $SilverDim), 11, 11, 6, 6)
    }
}

# tl — ATR Labels: price tag with value hole
function Draw-Tl([System.Drawing.Graphics]$g, [bool]$on) {
    $s = 28
    $halo = {
        param($gg, $p)
        $q = New-Object System.Drawing.Drawing2D.GraphicsPath
        Add-RRect $q 6 8 17 12 3
        $gg.DrawPath($p, $q)
        $gg.DrawLine($p, 3, 14, 6, 14)
        $q.Dispose()
    }
    Draw-Halo $g $on $halo
    $tag = New-Object System.Drawing.Drawing2D.GraphicsPath
    Add-RRect $tag 6 8 17 12 3
    $tf = State-Fill $on 6 8 17 12
    $g.FillPath($tf, $tag)
    $tag.Dispose(); $tf.Dispose()
    $g.DrawLine((State-Pen $on $s 1.6), 3, 14, 6, 14)
    $g.FillEllipse((Brush $Ink), 8.5, 12.5, 3, 3)
    if ($on) {
        $g.FillRectangle((Brush ([System.Drawing.Color]::FromArgb(170, 18, 22, 33))), 13, 11, 8, 1.6)
        $g.FillRectangle((Brush ([System.Drawing.Color]::FromArgb(170, 18, 22, 33))), 13, 14.2, 6, 1.6)
        $g.FillRectangle((Brush ([System.Drawing.Color]::FromArgb(170, 18, 22, 33))), 13, 17.4, 4, 1.6)
    } else {
        $g.FillRectangle((Brush ([System.Drawing.Color]::FromArgb(255, 14, 18, 28))), 13, 11, 8, 1.6)
        $g.FillRectangle((Brush ([System.Drawing.Color]::FromArgb(255, 14, 18, 28))), 13, 14.2, 6, 1.6)
        $g.FillRectangle((Brush ([System.Drawing.Color]::FromArgb(255, 14, 18, 28))), 13, 17.4, 4, 1.6)
    }
}

# dots — TH Labels: dotted level rows
function Draw-Dots([System.Drawing.Graphics]$g, [bool]$on) {
    $d = 3.4
    $yPos = @(7, 14, 21)
    foreach ($y in $yPos) {
        $rowFill = State-Fill $on 5 ([int]($y - 2)) 18 4
        $x = 5.0
        while ($x -le 23) {
            $g.FillEllipse($rowFill, [single]($x - $d/2), [single]($y - $d/2), [single]$d, [single]$d)
            $x += 4.5
        }
        $rowFill.Dispose()
    }
    if ($on) {
        $g.FillEllipse((Brush ([System.Drawing.Color]::FromArgb(230, 255, 255, 255))), 3.2, 12.6, 1.4, 1.4)
        $g.FillEllipse((Brush ([System.Drawing.Color]::FromArgb(230, 255, 255, 255))), 24.0, 12.6, 1.4, 1.4)
    }
}

# box — Timeframe Lock: padlock
function Draw-Box([System.Drawing.Graphics]$g, [bool]$on) {
    $s = 28
    $halo = {
        param($gg, $p)
        $q = New-Object System.Drawing.Drawing2D.GraphicsPath
        $q.AddArc(8, 4, 12, 12, 180, 180)
        $gg.DrawPath($p, $q)
        $r = New-Object System.Drawing.Drawing2D.GraphicsPath
        Add-RRect $r 5 13 18 11 3
        $gg.DrawPath($p, $r)
        $r.Dispose(); $q.Dispose()
    }
    Draw-Halo $g $on $halo
    $sh = New-Object System.Drawing.Drawing2D.GraphicsPath
    $sh.AddArc(8, 4, 12, 12, 180, 180)
    $g.DrawPath((State-Pen $on $s 2.4), $sh)
    $sh.Dispose()
    $body = New-Object System.Drawing.Drawing2D.GraphicsPath
    Add-RRect $body 5 13 18 11 3
    $bf = State-Fill $on 5 13 18 11
    $g.FillPath($bf, $body)
    $body.Dispose(); $bf.Dispose()
    if ($on) {
        $g.DrawLine((Pen ([System.Drawing.Color]::FromArgb(140, 255, 255, 255)) 1.0), 7, 14.5, 21, 14.5)
        $g.FillEllipse((Brush $Ink), 12.5, 16.5, 3.2, 3.2)
        $g.FillRectangle((Brush $Ink), 13.5, 19.2, 1.3, 3)
    } else {
        $g.FillEllipse((Brush $Ink), 12.5, 16.5, 3.2, 3.2)
        $g.FillRectangle((Brush $Ink), 13.5, 19.2, 1.3, 3)
    }
}

# custom — TH3 Frequency: frequency wave
function Draw-Custom([System.Drawing.Graphics]$g, [bool]$on) {
    $s = 28
    $halo = {
        param($gg, $p)
        $q = New-Object System.Drawing.Drawing2D.GraphicsPath
        $amp = 4.5; $midY = 14
        $pts = New-Object System.Collections.Generic.List[System.Drawing.PointF]
        for ($x = 0; $x -le 28; $x += 0.6) {
            $t = ($x - 14) / 5.0
            $y = $midY + $amp * [Math]::Sin($t * 1.4)
            $pts.Add(([System.Drawing.PointF]::new([float]$x, [float]$y)))
        }
        $q.AddLines($pts.ToArray())
        $gg.DrawPath($p, $q)
        $q.Dispose()
    }
    Draw-Halo $g $on $halo
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $amp = 4.5; $midY = 14
    $pts = New-Object System.Collections.Generic.List[System.Drawing.PointF]
    for ($x = 0; $x -le 28; $x += 0.6) {
        $t = ($x - 14) / 5.0
        $y = $midY + $amp * [Math]::Sin($t * 1.4)
        $pts.Add(([System.Drawing.PointF]::new([float]$x, [float]$y)))
    }
    if ($pts.Count -gt 1) { $p.AddLines($pts.ToArray()) }
    $wp = State-Pen $on $s 2.2
    $g.DrawPath($wp, $p)
    $p.Dispose(); $wp.Dispose()
    $kf = State-Fill $on 16 11 6 6
    $g.FillEllipse($kf, 16, 11, 6, 6)
    $kf.Dispose()
    $g.FillEllipse((Brush $Ink), 17.6, 12.6, 2.8, 2.8)
    if ($on) {
        $g.FillEllipse((Brush ([System.Drawing.Color]::FromArgb(200, 255, 255, 255))), 18.3, 13.3, 1.4, 1.4)
    }
}

# htf — HTF Candles: three candles, middle dominant
function Draw-Htf([System.Drawing.Graphics]$g, [bool]$on) {
    $s = 28
    $wicks = @(
        @(6,  8, 20, 10, 17),
        @(14, 4, 24, 7,  21),
        @(22, 10, 19, 12, 18)
    )
    $halo = {
        param($gg, $p)
        foreach ($k in $wicks) {
            $x = [float]$k[0]; $yT = [float]$k[1]; $yB = [float]$k[2]; $bT = [float]$k[3]; $bB = [float]$k[4]
            $gg.DrawLine($p, $x, $yT, $x, $bT)
            $gg.DrawLine($p, $x, $bB, $x, $yB)
        }
    }
    Draw-Halo $g $on $halo
    foreach ($k in $wicks) {
        $x  = [float]$k[0]; $yT = [float]$k[1]; $yB = [float]$k[2]; $bT = [float]$k[3]; $bB = [float]$k[4]
        $wp = State-Pen $on $s 1.4
        $g.DrawLine($wp, $x, $yT, $x, $bT)
        $g.DrawLine($wp, $x, $bB, $x, $yB)
        $wp.Dispose()
        $bodyW = 4; $bodyH = $bB - $bT; $bodyX = $x - 2; $bodyY = $bT
        $bf = State-Fill $on ([int]$bodyX) ([int]$bodyY) $bodyW ([int]$bodyH)
        $g.FillRectangle($bf, $bodyX, $bodyY, $bodyW, $bodyH)
        $bf.Dispose()
        if ($on) {
            $g.DrawLine((Pen ([System.Drawing.Color]::FromArgb(120, 255, 255, 255)) 1.0), ($bodyX + 0.7), ($bodyY + 1), ($bodyX + $bodyW - 0.7), ($bodyY + 1))
        }
    }
}

# pin — Custom Price Pin: map pin
function Draw-Pin([System.Drawing.Graphics]$g, [bool]$on) {
    $s = 28
    $halo = {
        param($gg, $p)
        $q = New-Object System.Drawing.Drawing2D.GraphicsPath
        $q.AddEllipse(7, 3, 14, 14)
        $q.AddPolygon(@(
            [System.Drawing.PointF]::new(14, 14),
            [System.Drawing.PointF]::new(12, 23),
            [System.Drawing.PointF]::new(16, 23)
        ))
        $gg.DrawPath($p, $q)
        $q.Dispose()
    }
    Draw-Halo $g $on $halo
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddEllipse(7, 3, 14, 14)
    $p.AddPolygon(@(
        [System.Drawing.PointF]::new(14, 14),
        [System.Drawing.PointF]::new(12, 23),
        [System.Drawing.PointF]::new(16, 23)
    ))
    if ($on) {
        $f = GradBrush 7 3 14 20 $GoldHi $GoldDeep
        $g.FillPath($f, $p)
        $f.Dispose()
        $g.FillEllipse((Brush $Ink), 10.5, 5.5, 5.5, 5.5)
        $g.FillEllipse((Brush $GoldHi), 11.5, 6.5, 3.5, 3.5)
        $g.FillEllipse((Brush ([System.Drawing.Color]::FromArgb(220, 255, 255, 255))), 12.3, 7.3, 1.6, 1.6)
    } else {
        $g.DrawPath((Pen $SilverDim 1.8), $p)
        $g.FillEllipse((Brush $SilverDim), 11, 6, 5, 5)
    }
    $p.Dispose()
    if ($on) { $g.FillEllipse((Brush $GoldDeep), 11, 23, 6, 2) }
    else     { $g.FillEllipse((Brush $SilverDim), 11, 23, 6, 2) }
}

# tools — Tools: gear
function Draw-Tools([System.Drawing.Graphics]$g, [bool]$on) {
    $s = 28
    $cx = 14.0; $cy = 14.0
    $outerR = 8.0
    $teeth = 8
    $mkGear = {
        $pts = New-Object System.Collections.Generic.List[System.Drawing.PointF]
        for ($i = 0; $i -lt $teeth * 2; $i++) {
            $ang = ([Math]::PI * 2 * $i) / ($teeth * 2) - [Math]::PI / 2
            $r = if ($i % 2 -eq 0) { $outerR } else { $outerR - 2.6 }
            $pts.Add(([System.Drawing.PointF]::new([float]($cx + $r * [Math]::Cos($ang)), [float]($cy + $r * [Math]::Sin($ang)))))
        }
        $pts.Add($pts[0])
        $gear = New-Object System.Drawing.Drawing2D.GraphicsPath
        $gear.AddLines($pts.ToArray())
        $gear.CloseFigure()
        return $gear
    }
    if ($on) {
        $hg = & $mkGear
        $hp = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(70, 255, 190, 80)), 4.0
        $g.DrawPath($hp, $hg)
        $hp.Dispose(); $hg.Dispose()
    }
    $gear = & $mkGear
    if ($on) {
        $f = GradBrush 5 5 18 18 $GoldHi $GoldDeep
        $g.FillPath($f, $gear)
        $f.Dispose()
    } else {
        $g.DrawPath((Pen $SilverDim 1.8), $gear)
    }
    $gear.Dispose()
    $g.FillEllipse((Brush $Ink), 11.4, 11.4, 5.2, 5.2)
    if ($on) {
        $cf = GradBrush 11 11 6 6 $GoldHi $Gold
        $g.FillEllipse($cf, 12.1, 12.1, 3.4, 3.4)
        $cf.Dispose()
    } else {
        $g.FillEllipse((Brush $SilverDim), 11.5, 11.5, 5, 5)
    }
}

# step — Step Mode Override: ascending steps with arrow
function Draw-Step([System.Drawing.Graphics]$g, [bool]$on) {
    $s = 28
    $mkSteps = {
        param($gg, $p)
        $q = New-Object System.Drawing.Drawing2D.GraphicsPath
        $q.AddLines(@(
            [System.Drawing.PointF]::new(4, 23),
            [System.Drawing.PointF]::new(11, 23),
            [System.Drawing.PointF]::new(11, 16),
            [System.Drawing.PointF]::new(18, 16),
            [System.Drawing.PointF]::new(18, 9),
            [System.Drawing.PointF]::new(25, 9)
        ))
        $gg.DrawPath($p, $q)
        $q.Dispose()
    }
    Draw-Halo $g $on $mkSteps
    $sp = State-Pen $on $s 2.4
    & $mkSteps $g $sp
    $sp.Dispose()
    $sf = State-Fill $on 2 21 7 5
    $g.FillRectangle($sf, 2.5, 21.5, 6.5, 4.5)
    $sf.Dispose()
    $af = State-Fill $on 21 4 6 7
    $pts = @(
        [System.Drawing.PointF]::new(21.5, 9.5),
        [System.Drawing.PointF]::new(26.5, 9.5),
        [System.Drawing.PointF]::new(24, 4.5)
    )
    $tri = New-Object System.Drawing.Drawing2D.GraphicsPath
    $tri.AddPolygon($pts)
    $g.FillPath($af, $tri)
    $tri.Dispose(); $af.Dispose()
}

# factor — Factor Override: slider
function Draw-Factor([System.Drawing.Graphics]$g, [bool]$on) {
    $s = 28
    if ($on) {
        $hp = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(70, 255, 190, 80)), 4.0
        $g.DrawLine($hp, 3, 14, 25, 14)
        $hp.Dispose()
    }
    $track = New-Object System.Drawing.Drawing2D.GraphicsPath
    Add-RRect $track 3 12 22 4 2
    $trackF = GradBrush 3 12 22 4 $InkSoft ([System.Drawing.Color]::FromArgb(255, 60, 68, 86))
    $g.FillPath($trackF, $track)
    $track.Dispose(); $trackF.Dispose()
    $fillBar = New-Object System.Drawing.Drawing2D.GraphicsPath
    Add-RRect $fillBar 4.5 13 12 2 1
    if ($on) {
        $fb = GradBrush 4 13 12 2 $GoldHi $GoldDeep
        $g.FillPath($fb, $fillBar)
        $fb.Dispose()
    } else {
        $g.FillPath((Brush $SilverDim), $fillBar)
    }
    $fillBar.Dispose()
    if ($on) {
        $knobF = GradBrush 13 7 9 9 $GoldHi $GoldDeep
        $g.FillEllipse($knobF, 13.5, 7.5, 9, 9)
        $knobF.Dispose()
    } else {
        $g.FillEllipse((Brush $Silver), 13.5, 7.5, 9, 9)
    }
    $g.FillEllipse((Brush $Ink), 15.5, 9.5, 5, 5)
    if ($on) {
        $g.FillEllipse((Brush $GoldHi), 16.5, 10.5, 3, 3)
        $g.FillEllipse((Brush ([System.Drawing.Color]::FromArgb(220, 255, 255, 255))), 17.2, 11.2, 1.4, 1.4)
    } else {
        $g.FillEllipse((Brush $Silver), 16.5, 10.5, 3, 3)
    }
    $g.DrawLine((Pen ([System.Drawing.Color]::FromArgb(170, 128, 136, 152)) 1.2), 8, 5, 8, 9)
    $g.DrawLine((Pen ([System.Drawing.Color]::FromArgb(170, 128, 136, 152)) 1.2), 22, 19, 22, 23)
}

# ---------- 28x28 ring icons ----------
$ringIcons = @{
    'zone'   = ${function:Draw-Zone}
    'chk'    = ${function:Draw-Chk}
    'tl'     = ${function:Draw-Tl}
    'dots'   = ${function:Draw-Dots}
    'box'    = ${function:Draw-Box}
    'custom' = ${function:Draw-Custom}
    'htf'    = ${function:Draw-Htf}
    'pin'    = ${function:Draw-Pin}
    'tools'  = ${function:Draw-Tools}
    'step'   = ${function:Draw-Step}
    'factor' = ${function:Draw-Factor}
}

foreach ($name in $ringIcons.Keys) {
    foreach ($state in @('off', 'on')) {
    try {
        $bmp = New-Bitmap 28 28
        $g = New-Gfx $bmp
        $drawer = $ringIcons[$name]
        & $drawer $g ($state -eq 'on')
        $g.Dispose()
        $path = Join-Path $Dir ("{0}_{1}.bmp" -f $name, $state)
        Save-Bmp32 $bmp $path
        Write-Host ("wrote {0}  ({1} bytes)" -f (Split-Path $path -Leaf), (Get-Item $path).Length)
    } catch {
        Write-Host ("FAILED {0}_{1}: {2}" -f $name, $state, $_.Exception.Message)
        Write-Host $_.ScriptStackTrace
    }
    }
}

# ---------- 52x52 circ (glass button skin) ----------
function Draw-Circ([System.Drawing.Graphics]$g, [bool]$on) {
    $size = 52
    $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
    Add-RRect $gp 1 1 ($size - 2) ($size - 2) 25
    if ($on) {
        $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            (New-Object System.Drawing.PointF 0, 0),
            (New-Object System.Drawing.PointF 0, $size),
            $InkSoft, $Ink)
    } else {
        $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            (New-Object System.Drawing.PointF 0, 0),
            (New-Object System.Drawing.PointF 0, $size),
            $Ink, $InkSoft)
    }
    $g.FillPath($lg, $gp)
    $lg.Dispose()
    $glow = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(50, 255, 190, 80)), 5.0
    $g.DrawEllipse($glow, 7.5, 7.5, $size - 15, $size - 15)
    $glow.Dispose()
    $hl = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(70, 255, 255, 255)), 1.0
    $g.DrawArc($hl, 7, 5, $size - 14, 16, 200, 140)
    $hl.Dispose()
    $edge = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(90, 255, 255, 255)), 1.0
    $g.DrawPath($edge, $gp)
    $edge.Dispose()
    if ($on) {
        $rp = GradPen $size $GoldHi $GoldDeep 2.0
    } else {
        $rp = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(180, 128, 136, 152)), 1.4
    }
    $g.DrawEllipse($rp, 5.5, 5.5, $size - 11, $size - 11)
    $rp.Dispose()
    $gp.Dispose()
}

foreach ($state in @('off', 'on')) {
    $bmp = New-Bitmap 52 52
    $g = New-Gfx $bmp
    Draw-Circ $g ($state -eq 'on')
    $g.Dispose()
    $path = Join-Path $Dir ("circ_{0}.bmp" -f $state)
    Save-Bmp32 $bmp $path
    Write-Host ("wrote {0}  ({1} bytes)" -f (Split-Path $path -Leaf), (Get-Item $path).Length)
}

# ---------- badge (12x12) ----------
$bmp = New-Bitmap 12 12
$g = New-Gfx $bmp
$gp = New-Object System.Drawing.Drawing2D.GraphicsPath
Add-RRect $gp 0 0 12 12 6
$bg = GradBrush 0 0 12 12 $GoldHi $GoldDeep
$g.FillPath($bg, $gp)
$bg.Dispose()
$g.DrawEllipse((Pen ([System.Drawing.Color]::FromArgb(150, 255, 255, 255)) 1.0), 2.5, 2.5, 7, 7)
$gp.Dispose()
$g.Dispose()
Save-Bmp32 $bmp (Join-Path $Dir 'badge.bmp')
Write-Host "wrote badge.bmp"

# ---------- orb_bg (56x56) ----------
$bmp = New-Bitmap 56 56
$g = New-Gfx $bmp
$gp = New-Object System.Drawing.Drawing2D.GraphicsPath
Add-RRect $gp 1 1 54 54 27
$lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.PointF 0, 0),
    (New-Object System.Drawing.PointF 0, 56),
    $InkSoft, $Ink)
$g.FillPath($lg, $gp)
$lg.Dispose()
$outerGlow = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(70, 255, 190, 80)), 4.0
$g.DrawEllipse($outerGlow, 5, 5, 46, 46)
$outerGlow.Dispose()
$rp = GradPen 56 $GoldHi $GoldDeep 1.8
$g.DrawEllipse($rp, 4, 4, 48, 48)
$rp.Dispose()
$hl = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(100, 255, 255, 255)), 1.2
$g.DrawArc($hl, 9, 8, 38, 18, 200, 140)
$hl.Dispose()
$edge = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(90, 255, 255, 255)), 1.0
$g.DrawPath($edge, $gp)
$edge.Dispose()
$gp.Dispose()
$g.Dispose()
Save-Bmp32 $bmp (Join-Path $Dir 'orb_bg.bmp')
Write-Host "wrote orb_bg.bmp"

# ---------- yy (32x32 — Biotak brand mark) ----------
$bmp = New-Bitmap 32 32
$g = New-Gfx $bmp
$font = New-Object System.Drawing.Font 'Segoe UI', 22, ([System.Drawing.FontStyle]::Bold)
$sf = New-Object System.Drawing.StringFormat
$sf.Alignment = [System.Drawing.StringAlignment]::Center
$sf.LineAlignment = [System.Drawing.StringAlignment]::Center
$rect = New-Object System.Drawing.RectangleF 0, 0, 32, 32
$gp = New-Object System.Drawing.Drawing2D.GraphicsPath
$gp.AddString('Y', $font.FontFamily, [int]$font.Style, $font.Size * 1.4, $rect, $sf)
$bg = GradBrush 4 2 24 28 $GoldHi $GoldDeep
$g.FillPath($bg, $gp)
$bg.Dispose()
$g.DrawPath((Pen ([System.Drawing.Color]::FromArgb(120, 255, 255, 255)) 1.0), $gp)
$gp.Dispose()
$font.Dispose()
$sf.Dispose()
$g.Dispose()
Save-Bmp32 $bmp (Join-Path $Dir 'yy.bmp')
Write-Host "wrote yy.bmp"

# ---------- knobs (14x14, 18x18) ----------
function New-Knob([int]$size, [string]$name) {
    $bmp = New-Bitmap $size $size
    $g = New-Gfx $bmp
    $r = ($size - 2) / 2.0
    $cx = $size / 2.0; $cy = $size / 2.0
    $rim = GradBrush ([int]($cx - $r)) ([int]($cy - $r)) $size $size $GoldHi $GoldDeep
    $g.FillEllipse($rim, [float]($cx - $r), [float]($cy - $r), [float]($r * 2), [float]($r * 2))
    $rim.Dispose()
    $g.FillEllipse((Brush $Ink), [float]($cx - $r + 2), [float]($cy - $r + 2), [float]($r * 2 - 4), [float]($r * 2 - 4))
    $g.FillEllipse((Brush ([System.Drawing.Color]::FromArgb(120, 255, 255, 255))),
        [float]($cx - $r + 3), [float]($cy - $r + 1.5), [float]($r * 2 - 6), [float]($r - 1.5))
    $g.Dispose()
    Save-Bmp32 $bmp (Join-Path $Dir $name)
    Write-Host "wrote $name"
}
New-Knob 14 'knob.bmp'
New-Knob 18 'pnl_knob.bmp'
New-Knob 18 'pnl_swknob.bmp'

# ---------- switch (46x24) ----------
foreach ($state in @('off', 'on')) {
    $bmp = New-Bitmap 46 24
    $g = New-Gfx $bmp
    $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
    Add-RRect $gp 0 0 46 24 12
    $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.PointF 0, 0),
        (New-Object System.Drawing.PointF 0, 24),
        $Ink, $InkSoft)
    $g.FillPath($lg, $gp)
    $lg.Dispose()
    if ($state -eq 'on') {
        $bp = GradPen 46 $GoldHi $GoldDeep 1.6
        $g.DrawPath($bp, $gp)
        $bp.Dispose()
        $knobX = 28
    } else {
        $g.DrawPath((Pen ([System.Drawing.Color]::FromArgb(180, 128, 136, 152)) 1.3), $gp)
        $knobX = 6
    }
    $gp.Dispose()
    $kr = 8
    $kcx = $knobX + $kr
    $kf = GradBrush ([int]($kcx - $kr)) ([int](12 - $kr)) ($kr * 2) ($kr * 2) $GoldHi $GoldDeep
    $g.FillEllipse($kf, [float]($kcx - $kr), [float](12 - $kr), [float]($kr * 2), [float]($kr * 2))
    $kf.Dispose()
    $g.FillEllipse((Brush $Ink), [float]($kcx - $kr + 2), [float](12 - $kr + 2), [float]($kr * 2 - 4), [float]($kr * 2 - 4))
    $g.FillEllipse((Brush ([System.Drawing.Color]::FromArgb(140, 255, 255, 255))),
        [float]($kcx - $kr + 2.5), [float](12 - $kr + 2), [float]($kr * 2 - 5), [float]($kr - 2))
    $g.Dispose()
    Save-Bmp32 $bmp (Join-Path $Dir ("pnl_sw_{0}.bmp" -f $state))
    Write-Host ("wrote pnl_sw_{0}.bmp" -f $state)
}

Write-Host "`nGenerator finished. Files written to: $Dir"

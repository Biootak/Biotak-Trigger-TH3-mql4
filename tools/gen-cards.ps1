# DEPRECATED 2026-09-03 — panel cards now come from tools/gen-th3-icons.js
# (opaque matte glass; this PS version writes non-transparent corners).
# See AGENTS.md R-ICONS / P-ICONS-02.
[CmdletBinding()]
param(
    [string]$OutputDir
)

Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
if (-not $OutputDir) {
    $OutputDir = Join-Path $PSScriptRoot '..\Files\Icons'
}
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

$Ink      = [System.Drawing.Color]::FromArgb(255,  18,  22,  33)
$InkSoft  = [System.Drawing.Color]::FromArgb(255,  26,  31,  46)
$InkDeep  = [System.Drawing.Color]::FromArgb(255,  10,  13,  22)
$Gold     = [System.Drawing.Color]::FromArgb(255, 255, 178,  56)
$GoldSoft = [System.Drawing.Color]::FromArgb(255, 255, 220, 130)

function New-Card([int]$w, [int]$h) {
    $bmp = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $bmp.SetResolution(96, 96)
    return $bmp
}

function Save-Bmp32([System.Drawing.Bitmap]$bmp, [string]$path) {
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Bmp)
}

# Build a premium glass card with soft alpha-rounded corners, dark vertical gradient,
# subtle gold accent bar at top, and 1px gold/silver hairline border.
function Draw-Card([System.Drawing.Graphics]$g, [int]$w, [int]$h) {
    # 1) clear background (already 0,0,0,0 from new bitmap)
    $radius = 14
    $pad = 1

    # 2) rounded-rect clipping region so corner anti-alias stays clean
    $clip = New-Object System.Drawing.Drawing2D.GraphicsPath
    $clip.AddArc($pad, $pad, $radius*2, $radius*2, 180, 90)
    $clip.AddArc($w - $pad - $radius*2, $pad, $radius*2, $radius*2, 270, 90)
    $clip.AddArc($w - $pad - $radius*2, $h - $pad - $radius*2, $radius*2, $radius*2, 0, 90)
    $clip.AddArc($pad, $h - $pad - $radius*2, $radius*2, $radius*2, 90, 90)
    $clip.CloseFigure()
    $g.SetClip($clip)

    # 3) deep gradient body (top-down: ink -> ink-soft -> ink-deep)
    $rect = New-Object System.Drawing.RectangleF $pad, $pad, ($w - 2*$pad), ($h - 2*$pad)
    $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.PointF 0, 0),
        (New-Object System.Drawing.PointF 0, $h),
        $Ink, $InkDeep
    )
    $cb = New-Object System.Drawing.Drawing2D.ColorBlend
    $cb.Colors = @($InkDeep, $InkSoft, $Ink)
    $cb.Positions = @(0.0, 0.55, 1.0)
    $lg.InterpolationColors = $cb
    $g.FillRectangle($lg, $rect)
    $lg.Dispose()

    # 4) subtle inner top highlight
    $hl = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(40, 255, 255, 255)), 1.0
    $g.DrawLine($hl, $radius+2, 2, $w - $radius - 2, 2)
    $hl.Dispose()

    # 5) gold accent bar at the very top (3px tall)
    $accent = New-Object System.Drawing.RectangleF $radius, 0, ($w - 2*$radius), 3
    $goldLG = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.PointF 0, 0),
        (New-Object System.Drawing.PointF $w, 0),
        $Gold, $GoldSoft
    )
    $g.FillRectangle($goldLG, $accent)
    $goldLG.Dispose()
    # center darker line for definition
    $mid = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(160, 0, 0, 0)), 1.0
    $g.DrawLine($mid, $radius, 3, $w - $radius, 3)
    $mid.Dispose()

    # 6) bottom subtle separator
    $sep = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(60, 255, 255, 255)), 1.0
    $g.DrawLine($sep, $radius+4, $h-4, $w - $radius - 4, $h-4)
    $sep.Dispose()

    $g.ResetClip()
    $clip.Dispose()

    # 7) outer hairline border (on top, after reset clip)
    $border = New-Object System.Drawing.Drawing2D.GraphicsPath
    $border.AddArc(0.5, 0.5, $radius*2, $radius*2, 180, 90)
    $border.AddArc($w - 0.5 - $radius*2, 0.5, $radius*2, $radius*2, 270, 90)
    $border.AddArc($w - 0.5 - $radius*2, $h - 0.5 - $radius*2, $radius*2, $radius*2, 0, 90)
    $border.AddArc(0.5, $h - 0.5 - $radius*2, $radius*2, $radius*2, 90, 90)
    $border.CloseFigure()
    $borderPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(150, 255, 178, 56)), 1.0
    $g.DrawPath($borderPen, $border)
    $border.Dispose()
    $borderPen.Dispose()
}

# Build cards 3..12 (heights 282..732, +50 each)
for ($card = 3; $card -le 12; $card++) {
    $h = 282 + ($card - 3) * 50
    $w = 340
    $bmp = New-Card $w $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    Draw-Card $g $w $h
    $g.Dispose()
    $path = Join-Path $OutputDir ("pnl_card{0}.bmp" -f $card)
    Save-Bmp32 $bmp $path
    Write-Host ("wrote pnl_card{0}.bmp  ({1} x {2}, {3} bytes)" -f $card, $w, $h, (Get-Item $path).Length)
}

Write-Host "`nPanel card generator finished. Output: $OutputDir"

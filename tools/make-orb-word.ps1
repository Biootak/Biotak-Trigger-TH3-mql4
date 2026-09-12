<#
.SYNOPSIS
    Biotak Trigger TH3 - OPEN-state orb master builder ("TRex" wordmark).

    panel_ring_menu_preview.html (the ring-menu spec) declares TWO orb states:

      closed menu  -> the bow medallion            (orb_bg.bmp, unchanged)
      open menu    -> "TRex" on the same 64px disc (orb_word.bmp, THIS script)

    The spec is explicit that the word REPLACES the bow art instead of sitting on
    top of it, and that the separate skin must cover the same 64px disc with the
    gold halo so the bow artwork itself stays untouched.

    So the plate under the word is the medallion's OWN interior: a strongly
    alpha-weighted blurred copy of orb-bow-master.bgra, pushed part of the way
    toward a dark disc base so the bow reads as a faint texture instead of a
    second subject competing with the word. The blur is a separable
    alpha-weighted box blur (weight = alpha, running sums) so the transparent
    surround can never bleed dark pixels inward. Every pixel outside the plate
    radius - the outer ring, the halo - is copied byte-for-byte from the bow
    master (VERIFIED at the end of this script, not assumed), so the two states
    share one chrome and the orb only changes in the middle.

    Two knobs matter and both were wrong at first:
      -BlurPx  earlier builds ran 16 passes of a 3x3 binomial (= sigma 2.8px on a
               60px disc), which only softened the bow edges; the shape stayed
               perfectly readable behind the word. Now a real sigma, default 5px.
      -Fade     blur ALONE does not make the bow recede: a softened bright blob
               is still a bright blob. This blends the blurred plate toward
               -BaseHex, which is what actually lets the wordmark dominate.

    Text = Arial Bold, per-glyph tracking (+0.9px, the preview's
    letter-spacing), split positional at -SplitAt: "TR" in the stamp blue
    (clrBlue) and "ex" in the stamp red (clrRed), each half with its own
    glow behind it (blurred text mask) and the crisp mask on top - all
    composited in straight alpha, then premultiplied into the master
    exactly like make-orb-bow.ps1 does.

    Output: tools/orb-word-master.bgra (MxM top-down premultiplied BGRA), the
    single source of truth tools/gen-th3-icons.js embeds into
    Files/Icons/orb_word.bmp on every regen (P-ICONS-04).

    NOTE: keep this file ASCII-only. PowerShell 5.1 decodes a BOM-less .ps1 as
    ANSI, so a UTF-8 em-dash becomes a smart quote and breaks the parser.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-orb-word.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-orb-word.ps1 -Label 'TRex' -BlurPx 6 -Fade 0.6
#>
[CmdletBinding()]
param(
    [int]$MasterSize = 72,
    [string]$Label = 'TRex',
    [double]$PlateR = 0.72,      # plate radius as a fraction of the disc radius.
                                 # Stops inside the gold ring's inner rim
                                 # (measured at ~0.80R), so the shared chrome is
                                 # never entered and the feather lands on the
                                 # ring's dark inner groove.
    [double]$Feather = 0.10,     # soft edge of the plate (fraction of the disc radius)
    [double]$BlurPx = 5.0,       # blur sigma in MASTER pixels for the plate art
    [double]$BlurPasses = 3,     # box passes; 3 approximates a gaussian
    [double]$Fade = 0.70,        # push the blurred plate this far toward -BaseHex
    [string]$BaseHex = '#141A23',# the dark disc base the plate fades into
    [double]$TextPx = 14.5,      # preview .orbtext is 15px on a 64px orb
    [double]$Tracking = 0.9,     # preview letter-spacing: .9px
    [int]$SplitAt = 2,           # first SplitAt glyphs wear stamp blue ("TR"),
                                 # the rest wear stamp red ("ex")
    [double]$GlowSpread = 0.55,  # glow strength behind the word
    [double]$GlowPx = 1.7        # glow sigma in master px (the old 6 binomial
                                 # passes were ~1.7px, kept at that size so the
                                 # word's halo does not change)
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$InMaster  = Join-Path $PSScriptRoot 'orb-bow-master.bgra'
$OutMaster = Join-Path $PSScriptRoot 'orb-word-master.bgra'

if (-not (Test-Path -LiteralPath $InMaster)) {
    throw "missing $InMaster; run powershell -File tools\make-orb-bow.ps1 first"
}
if (Test-Path -LiteralPath $OutMaster) {
    Copy-Item -LiteralPath $OutMaster -Destination ($OutMaster + '.prev') -Force
}

$M = $MasterSize
$n = $M * $M

# ---------------------------------------------------------------- ingest
$raw = [System.IO.File]::ReadAllBytes($InMaster)
if ($raw.Length -ne $n * 4) { throw "orb-bow-master.bgra bad size: $($raw.Length) (want $($n * 4))" }

# premultiplied BGRA -> straight RGBA in double arrays (0..255)
$sr = New-Object double[] $n
$sg = New-Object double[] $n
$sb = New-Object double[] $n
$sa = New-Object double[] $n
for ($i = 0; $i -lt $n; $i++) {
    $oo = $i * 4
    $a  = [double]$raw[$oo + 3]
    $sa[$i] = $a
    if ($a -gt 0.0) {
        $k = 255.0 / $a
        $b = [double]$raw[$oo] * $k
        $g = [double]$raw[$oo + 1] * $k
        $r = [double]$raw[$oo + 2] * $k
        if ($b -gt 255.0) { $b = 255.0 }
        if ($g -gt 255.0) { $g = 255.0 }
        if ($r -gt 255.0) { $r = 255.0 }
        $sb[$i] = $b; $sg[$i] = $g; $sr[$i] = $r
    }
}

# ---------------------------------------------------------------- disc fit
# alpha profile of the middle row + middle column -> centre and radius. The
# master is a disc on a transparent canvas, so this needs no hard-coded geometry.
$c0 = [int]($M / 2)
$minX = -1; $maxX = -1; $minY = -1; $maxY = -1
for ($x = 0; $x -lt $M; $x++) {
    if ($sa[$c0 * $M + $x] -gt 200.0) { if ($minX -lt 0) { $minX = $x }; $maxX = $x }
}
for ($y = 0; $y -lt $M; $y++) {
    if ($sa[$y * $M + $c0] -gt 200.0) { if ($minY -lt 0) { $minY = $y }; $maxY = $y }
}
if ($maxX -lt 0 -or $maxY -lt 0) { throw 'disc fit failed: no opaque pixels on the middle row/column' }
$cx = ($minX + $maxX) / 2.0
$cy = ($minY + $maxY) / 2.0
$radius = (($maxX - $minX) + ($maxY - $minY)) / 4.0
if ($radius -lt $M * 0.35) { throw "disc fit looks wrong: r=$radius on a $M canvas" }
Write-Host ("disc: center=({0:0.0},{1:0.0}) r={2:0.0}" -f $cx, $cy, $radius)

# ---------------------------------------------------------------- weighted blur
# Alpha-weighted SEPARABLE box blur driven by running sums: O(1) per pixel per
# pass, independent of the radius, so a real sigma costs the same as a tiny one.
# Three box passes approximate a gaussian of sigma ~ radius.
#
# This replaced 16 passes of a 3x3 binomial (sigma 2.8px on a 60px disc), which
# only softened the bow's edges - the shape stayed fully readable behind the
# wordmark, which is exactly what the user reported on the chart.
#
# Weighting by alpha means transparent pixels contribute nothing, so the disc
# edge can never bleed darkness inward. Border taps are CLAMPED, and because the
# slide subtracts clamped(x-rad) while adding clamped(x+rad+1), the clamped
# duplicates are counted the right number of times.
function Invoke-BoxBlur([double[]]$pr, [double[]]$pg, [double[]]$pb, [double[]]$pa, [int]$W, [int]$H, [int]$rad, [int]$passes) {
    $rr = $pr; $gg = $pg; $bb = $pb
    for ($p = 0; $p -lt $passes; $p++) {
        # ---- horizontal
        $hr = New-Object double[] ($W * $H)
        $hg = New-Object double[] ($W * $H)
        $hb = New-Object double[] ($W * $H)
        for ($y = 0; $y -lt $H; $y++) {
            $row0 = $y * $W
            $ar = 0.0; $ag = 0.0; $ab = 0.0; $aa = 0.0
            for ($k = -$rad; $k -le $rad; $k++) {
                $x = $k
                if ($x -lt 0) { $x = 0 }
                if ($x -gt $W - 1) { $x = $W - 1 }
                $i = $row0 + $x
                $aw = $pa[$i]
                $ar = $ar + $rr[$i] * $aw; $ag = $ag + $gg[$i] * $aw
                $ab = $ab + $bb[$i] * $aw; $aa = $aa + $aw
            }
            for ($x = 0; $x -lt $W; $x++) {
                $o = $row0 + $x
                if ($aa -gt 0.0) { $hr[$o] = $ar / $aa; $hg[$o] = $ag / $aa; $hb[$o] = $ab / $aa }
                else { $hr[$o] = $rr[$o]; $hg[$o] = $gg[$o]; $hb[$o] = $bb[$o] }
                $xin = $x - $rad
                if ($xin -lt 0) { $xin = 0 }
                $xout = $x + $rad + 1
                if ($xout -gt $W - 1) { $xout = $W - 1 }
                $ia = $row0 + $xin; $ib = $row0 + $xout
                $w1 = $pa[$ia]
                $ar = $ar - $rr[$ia] * $w1; $ag = $ag - $gg[$ia] * $w1
                $ab = $ab - $bb[$ia] * $w1; $aa = $aa - $w1
                $w2 = $pa[$ib]
                $ar = $ar + $rr[$ib] * $w2; $ag = $ag + $gg[$ib] * $w2
                $ab = $ab + $bb[$ib] * $w2; $aa = $aa + $w2
            }
        }
        # ---- vertical (same slide, stride = W)
        $vr = New-Object double[] ($W * $H)
        $vg = New-Object double[] ($W * $H)
        $vb = New-Object double[] ($W * $H)
        for ($x = 0; $x -lt $W; $x++) {
            $ar = 0.0; $ag = 0.0; $ab = 0.0; $aa = 0.0
            for ($k = -$rad; $k -le $rad; $k++) {
                $y = $k
                if ($y -lt 0) { $y = 0 }
                if ($y -gt $H - 1) { $y = $H - 1 }
                $i = $y * $W + $x
                $aw = $pa[$i]
                $ar = $ar + $hr[$i] * $aw; $ag = $ag + $hg[$i] * $aw
                $ab = $ab + $hb[$i] * $aw; $aa = $aa + $aw
            }
            for ($y = 0; $y -lt $H; $y++) {
                $o = $y * $W + $x
                if ($aa -gt 0.0) { $vr[$o] = $ar / $aa; $vg[$o] = $ag / $aa; $vb[$o] = $ab / $aa }
                else { $vr[$o] = $hr[$o]; $vg[$o] = $hg[$o]; $vb[$o] = $hb[$o] }
                $yin = $y - $rad
                if ($yin -lt 0) { $yin = 0 }
                $yout = $y + $rad + 1
                if ($yout -gt $H - 1) { $yout = $H - 1 }
                $ia = $yin * $W + $x; $ib = $yout * $W + $x
                $w1 = $pa[$ia]
                $ar = $ar - $hr[$ia] * $w1; $ag = $ag - $hg[$ia] * $w1
                $ab = $ab - $hb[$ia] * $w1; $aa = $aa - $w1
                $w2 = $pa[$ib]
                $ar = $ar + $hr[$ib] * $w2; $ag = $ag + $hg[$ib] * $w2
                $ab = $ab + $hb[$ib] * $w2; $aa = $aa + $w2
            }
        }
        $rr = $vr; $gg = $vg; $bb = $vb
    }
    return ,@($rr, $gg, $bb)
}

$radPx = [int][Math]::Round($BlurPx)
if ($radPx -lt 1) { $radPx = 1 }
$blurred = Invoke-BoxBlur $sr $sg $sb $sa $M $M $radPx $BlurPasses
$br = $blurred[0]; $bg = $blurred[1]; $bb2 = $blurred[2]

# ---------------------------------------------------------------- plate compose
# The bow sits in the MIDDLE of the disc; the gold ring and halo begin at about
# 0.80R, so -PlateR (default 0.72R) plus its feather (0.67R..0.77R) lands the
# transition on the ring's dark inner groove instead of on gold.
$baseCol = [System.Drawing.ColorTranslator]::FromHtml($BaseHex)
$baseR = [double]$baseCol.R; $baseG = [double]$baseCol.G; $baseB = [double]$baseCol.B
$R0 = ($PlateR - $Feather / 2.0) * $radius
$R1 = ($PlateR + $Feather / 2.0) * $radius
for ($y = 0; $y -lt $M; $y++) {
    $dy = ($y + 0.5) - $cy
    for ($x = 0; $x -lt $M; $x++) {
        $dx = ($x + 0.5) - $cx
        $d = [Math]::Sqrt($dx * $dx + $dy * $dy)
        if ($d -ge $R1) { continue }                      # chrome untouched
        $i = $y * $M + $x
        if ($sa[$i] -le 0.0) { continue }                 # outside the disc
        if ($d -le $R0) { $t = 1.0 }
        else {
            $u = ($d - $R0) / ($R1 - $R0)
            $t = 1.0 - ($u * $u * (3.0 - 2.0 * $u))       # smoothstep
        }
        # Blur alone leaves the bow a soft-but-bright blob, which still fights
        # the wordmark for attention. Pushing it -Fade toward the dark disc base
        # is what actually makes it recede into a faint texture.
        $nr = $br[$i] * (1.0 - $Fade) + $baseR * $Fade
        $ng = $bg[$i] * (1.0 - $Fade) + $baseG * $Fade
        $nb = $bb2[$i] * (1.0 - $Fade) + $baseB * $Fade
        $sr[$i] = $sr[$i] * (1.0 - $t) + $nr * $t
        $sg[$i] = $sg[$i] * (1.0 - $t) + $ng * $t
        $sb[$i] = $sb[$i] * (1.0 - $t) + $nb * $t
    }
}

# ---------------------------------------------------------------- wordmark masks
# TWO masks, one per wordmark half, so "TR" wears the stamp blue (clrBlue)
# and "ex" the stamp red (clrRed). Layout is measured ONCE over the whole
# label, so the split moves zero advances: both halves land exactly where
# the old uniform word did.
if ($SplitAt -lt 0) { $SplitAt = 0 }
if ($SplitAt -gt $Label.Length) { $SplitAt = $Label.Length }
function Read-AlphaMask($bmp) {
    $rect = New-Object System.Drawing.Rectangle(0, 0, $M, $M)
    $lk = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $stride = $lk.Stride
        $tmp = New-Object byte[] ($stride * $M)
        [System.Runtime.InteropServices.Marshal]::Copy($lk.Scan0, $tmp, 0, $tmp.Length)
        $mk = New-Object double[] $n
        for ($yy = 0; $yy -lt $M; $yy++) {
            $rowOff = $yy * $stride
            $mkOff = $yy * $M
            for ($xx = 0; $xx -lt $M; $xx++) {
                $mk[$mkOff + $xx] = [double]($tmp[$rowOff + $xx * 4 + 3]) / 255.0
            }
        }
        return ,$mk
    } finally { $bmp.UnlockBits($lk) }
}
function Draw-WordPart($g, $font, $fmt, $brush, $text, $penStart, $baseY, $adv, $advFrom) {
    $pen = $penStart
    for ($c = 0; $c -lt $text.Length; $c++) {
        $g.DrawString($text.Substring($c, 1), $font, $brush, [single]$pen, [single]$baseY, $fmt)
        $pen += $adv[$advFrom + $c] + $Tracking
    }
}
$tmpBmp = New-Object System.Drawing.Bitmap($M, $M, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$maskTR = $null
$maskEX = $null
try {
    $g = [System.Drawing.Graphics]::FromImage($tmpBmp)
    try {
        $g.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $font = New-Object System.Drawing.Font('Arial', [single]$TextPx, [System.Drawing.FontStyle]::Bold)
        $fmt = [System.Drawing.StringFormat]::GenericTypographic
        $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 255, 255))
        try {
            $adv = New-Object double[] ($Label.Length)
            $total = 0.0
            for ($c = 0; $c -lt $Label.Length; $c++) {
                $ch = $Label.Substring($c, 1)
                # NOT $m: PowerShell variable names are case-INsensitive, so
                # naming this $m clobbered the master size $M (set at the top)
                # with a SizeF and every later $M use threw
                # "Cannot convert Rectangle...  to type System.Int32".
                $meas = $g.MeasureString($ch, $font, [System.Drawing.PointF]::new(0, 0), $fmt)
                $adv[$c] = $meas.Width
                $total += $meas.Width
            }
            $total += $Tracking * ($Label.Length - 1)
            $pen0 = $cx - $total / 2.0
            $baseY = $cy - $font.GetHeight($g) / 2.0
            Draw-WordPart $g $font $fmt $brush $Label.Substring(0, $SplitAt) $pen0 $baseY $adv 0
            $maskTR = Read-AlphaMask $tmpBmp
            $g.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
            $pen1 = $pen0
            for ($c = 0; $c -lt $SplitAt; $c++) { $pen1 += $adv[$c] + $Tracking }
            Draw-WordPart $g $font $fmt $brush $Label.Substring($SplitAt) $pen1 $baseY $adv $SplitAt
            $maskEX = Read-AlphaMask $tmpBmp
        } finally { $brush.Dispose(); $font.Dispose() }
    } finally { $g.Dispose() }
} finally { $tmpBmp.Dispose() }

# ---------------------------------------------------------------- glow + word
# Each half glows in its OWN ink (blue halo behind TR, red behind ex), so the
# two halos never muddy each other. The glow blur runs with weight = 1
# everywhere.
$ones = New-Object double[] $n
for ($i = 0; $i -lt $n; $i++) { $ones[$i] = 1.0 }
$glowRad = [int][Math]::Round($GlowPx)
if ($glowRad -lt 1) { $glowRad = 1 }
$glTR = Invoke-BoxBlur $maskTR $maskTR $maskTR $ones $M $M $glowRad 3
$glEX = Invoke-BoxBlur $maskEX $maskEX $maskEX $ones $M $M $glowRad 3
$glowTR = $glTR[0]
$glowEX = $glEX[0]
$trR = 0.0; $trG = 0.0; $trB = 255.0          # clrBlue - the stamp's TR
$exR = 255.0; $exG = 0.0; $exB = 0.0          # clrRed - the stamp's ex

for ($y = 0; $y -lt $M; $y++) {
    for ($x = 0; $x -lt $M; $x++) {
        $i = $y * $M + $x
        if ($sa[$i] -le 0.0) { continue }
        $gv = $glowTR[$i] * $GlowSpread
        if ($gv -gt 1.0) { $gv = 1.0 }
        if ($gv -gt 0.0) {                                # blue glow behind TR
            $sr[$i] = $sr[$i] * (1.0 - $gv) + $trR * $gv
            $sg[$i] = $sg[$i] * (1.0 - $gv) + $trG * $gv
            $sb[$i] = $sb[$i] * (1.0 - $gv) + $trB * $gv
        }
        $gv = $glowEX[$i] * $GlowSpread
        if ($gv -gt 1.0) { $gv = 1.0 }
        if ($gv -gt 0.0) {                                # red glow behind ex
            $sr[$i] = $sr[$i] * (1.0 - $gv) + $exR * $gv
            $sg[$i] = $sg[$i] * (1.0 - $gv) + $exG * $gv
            $sb[$i] = $sb[$i] * (1.0 - $gv) + $exB * $gv
        }
        $cov = $maskTR[$i]
        if ($cov -gt 0.0) {                               # crisp TR on top
            $sr[$i] = $sr[$i] * (1.0 - $cov) + $trR * $cov
            $sg[$i] = $sg[$i] * (1.0 - $cov) + $trG * $cov
            $sb[$i] = $sb[$i] * (1.0 - $cov) + $trB * $cov
        }
        $cov = $maskEX[$i]
        if ($cov -gt 0.0) {                               # crisp ex on top
            $sr[$i] = $sr[$i] * (1.0 - $cov) + $exR * $cov
            $sg[$i] = $sg[$i] * (1.0 - $cov) + $exG * $cov
            $sb[$i] = $sb[$i] * (1.0 - $cov) + $exB * $cov
        }
    }
}
# one combined mask/glow for the chrome check below (the wordmark may run
# over the plate rim, but never past 0.80R)
$mask = New-Object double[] $n
$glow = New-Object double[] $n
for ($i = 0; $i -lt $n; $i++) {
    if ($maskTR[$i] -gt $maskEX[$i]) { $mask[$i] = $maskTR[$i] } else { $mask[$i] = $maskEX[$i] }
    if ($glowTR[$i] -gt $glowEX[$i]) { $glow[$i] = $glowTR[$i] } else { $glow[$i] = $glowEX[$i] }
}

# ---------------------------------------------------------------- premultiply + write
$out = New-Object byte[] ($n * 4)
for ($i = 0; $i -lt $n; $i++) {
    $oo = $i * 4
    $a = $sa[$i]
    if ($a -le 0.0) { $out[$oo] = 0; $out[$oo + 1] = 0; $out[$oo + 2] = 0; $out[$oo + 3] = 0; continue }
    $b = $sb[$i] * $a / 255.0
    $g = $sg[$i] * $a / 255.0
    $r = $sr[$i] * $a / 255.0
    if ($b -gt 255.0) { $b = 255.0 }
    if ($g -gt 255.0) { $g = 255.0 }
    if ($r -gt 255.0) { $r = 255.0 }
    $out[$oo]     = [byte][Math]::Round($b)
    $out[$oo + 1] = [byte][Math]::Round($g)
    $out[$oo + 2] = [byte][Math]::Round($r)
    $out[$oo + 3] = [byte][Math]::Round($a)
}

# self-check - never ship a white square (same contract as make-orb-bow.ps1)
# EVERY product is parenthesised on purpose: in PowerShell the comma of an
# array literal binds TIGHTER than '*', so `@(0, ($M - 1) * 4)` is really
# `@((0, ($M-1)) * 4)` - an array repeated 4 times, i.e. an Object[] -> the
# self-check then fails with the baffling
#   Cannot convert the "System.Object[]" value ... to type "System.UInt32".
# That is what kept orb_word.bmp from ever being generated.
$corners = @(0, (($M - 1) * 4), ((($M - 1) * $M) * 4), ((($M * $M) - 1) * 4))
foreach ($oo in $corners) {
    if ($out[$oo + 3] -gt 127) { throw 'corner still opaque, disc mask failed' }
}
$mid = ((([int]($M / 2)) * $M) + [int]($M / 2)) * 4
if ($out[$mid + 3] -lt 200) { throw 'center transparent, disc mask failed' }
Write-Host 'orb word master: disc check OK (corners transparent, center opaque)'

# ---------------------------------------------------------------- chrome check
# The closed and open states must share ONE ring and halo, so the plate overlay
# must not leak: every OPAQUE pixel outside the plate that the wordmark does not
# itself cover has to come back identical to orb-bow-master.bgra. Proven here,
# not by eye.
#
# Two exclusions, both learned the hard way:
#  - alpha < 255 is skipped. A 32bpp BMP may legally carry RGB under a=0 (the
#    disc's transparent surround does) and the premultiply pass normalises those
#    to 0, which first reported a 241-level "change" on invisible bytes.
#  - ink and glow pixels are skipped, because the wordmark IS allowed to run over
#    the plate rim. Its overhang is measured instead of ignored, so it can never
#    grow unnoticed: 0 px past 0.80R means the gold ring is still untouched.
$outer = 0
$soft = 0
$inkOut = 0
$inkRing = 0
$maxDelta = 0
$softDelta = 0
$worstAt = '-'
$Rgold = 0.80 * $radius          # where the gold ring's inner rim starts
for ($y = 0; $y -lt $M; $y++) {
    $dy = ($y + 0.5) - $cy
    for ($x = 0; $x -lt $M; $x++) {
        $dx = ($x + 0.5) - $cx
        $d = [Math]::Sqrt($dx * $dx + $dy * $dy)
        if ($d -lt $R1) { continue }
        $i = $y * $M + $x
        $oo = $i * 4
        if (($mask[$i] -gt 0.0) -or (($glow[$i] * $GlowSpread) -gt 0.0)) {
            $inkOut = $inkOut + 1
            if ($d -ge $Rgold) { $inkRing = $inkRing + 1 }
            continue
        }
        if ($raw[$oo + 3] -eq 255) {
            $outer = $outer + 1
            if ($out[$oo + 3] -ne 255) {
                $maxDelta = 255
                $worstAt = "x=$x y=$y alpha lost by the plate overlay"
                continue
            }
            for ($ch = 0; $ch -lt 3; $ch++) {
                $dv = [Math]::Abs([int]$out[$oo + $ch] - [int]$raw[$oo + $ch])
                if ($dv -gt $maxDelta) {
                    $maxDelta = $dv
                    $worstAt = "x=$x y=$y ch=$ch d=$($d.ToString('0.0'))r in=$($raw[$oo]),$($raw[$oo+1]),$($raw[$oo+2]) out=$($out[$oo]),$($out[$oo+1]),$($out[$oo+2])"
                }
            }
        } else {
            $soft = $soft + 1
            $dv = [Math]::Abs([int]$out[$oo + 3] - [int]$raw[$oo + 3])
            if ($dv -gt $softDelta) { $softDelta = $dv }
        }
    }
}
Write-Host ("chrome check: {0} clean opaque px outside the plate, max RGB delta {1}" -f $outer, $maxDelta)
if ($maxDelta -gt 0) { Write-Host ("  worst: {0}" -f $worstAt) }
Write-Host ("chrome check: {0} feathered px (alpha delta {1}); wordmark overhang: {2} px past the plate, {3} of them past 0.80R" -f $soft, $softDelta, $inkOut, $inkRing)
if ($maxDelta -gt 0) { throw 'open-state orb altered the shared chrome: the ring/halo must be identical in both states' }

[System.IO.File]::WriteAllBytes($OutMaster, $out)
Write-Host "Wrote $OutMaster ($($out.Length) bytes premultiplied BGRA)"
Write-Host 'Done. Next: node tools/gen-th3-icons.js  (embeds it into Files/Icons/orb_word.bmp)'

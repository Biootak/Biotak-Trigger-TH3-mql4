param([string]$Path,[int]$X0=40,[int]$X1=350,[int]$Y0=110,[int]$Y1=340,[int]$MinInk=3,[string]$Mode="dark",[string]$Label="")
Add-Type -AssemblyName System.Drawing
$bmp = [System.Drawing.Bitmap]::FromFile($Path)
$w = $bmp.Width; $h = $bmp.Height
$rect = New-Object System.Drawing.Rectangle 0,0,$w,$h
$clone = New-Object System.Drawing.Bitmap $w,$h,([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($clone)
$g.DrawImage($bmp, $rect); $g.Dispose()
$data = $clone.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$stride = $data.Stride
$bytes = New-Object byte[] ($stride * $h)
[System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
$clone.UnlockBits($data)

Write-Output ("--- {0}  {1}x{2}  x{3}..{4} y{5}..{6} mode={7}" -f $Label, $w, $h, $X0, $X1, $Y0, $Y1, $Mode)
$prev = $false; $start = 0; $peak = 0
for ($y = $Y0; $y -lt $Y1; $y++) {
  $ink = 0
  for ($x = $X0; $x -lt $X1; $x += 2) {
    $i = $y * $stride + $x * 4
    $b = $bytes[$i]; $gg = $bytes[$i+1]; $r = $bytes[$i+2]
    $mx = [Math]::Max($r, [Math]::Max($gg, $b)); $mn = [Math]::Min($r, [Math]::Min($gg, $b))
    $d = $mx - $mn
    if ($Mode -eq "dark") { if ($mx -lt 120 -and $d -lt 60) { $ink++ } }
    elseif ($Mode -eq "blue") { if ($b -gt ($r + 60) -and $b -gt ($gg + 40)) { $ink++ } }
    elseif ($Mode -eq "dblue") { if ($b -gt ($r + 60) -and $b -gt ($gg + 40) -and $r -lt 90) { $ink++ } }
    elseif ($Mode -eq "wide") { if ($mx -lt 130 -or $d -gt 90) { $ink++ } }
    elseif ($Mode -eq "full") { if ($mx -lt 200 -and $d -lt 90) { $ink++ } }
  }
  if ($ink -ge $MinInk) {
    if (-not $prev) { $prev = $true; $start = $y; $peak = 0 }
    if ($ink -gt $peak) { $peak = $ink }
  } else {
    if ($prev) { Write-Output ("  ROW {0}..{1} peak={2}" -f $start, ($y-1), $peak); $prev = $false }
  }
}
if ($prev) { Write-Output ("  ROW {0}..{1} peak={2}" -f $start, ($Y1-1), $peak) }
$bmp.Dispose()

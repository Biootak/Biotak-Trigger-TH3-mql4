param([string]$Path,[string]$Rows,[int]$X0=0,[int]$X1=1600,[string]$Mode="dark")
Add-Type -AssemblyName System.Drawing
$bmp = [System.Drawing.Bitmap]::FromFile($Path)
$w = $bmp.Width; $h = $bmp.Height
foreach ($rs in $Rows.Split(",")) {
  $parts = $rs.Split("-")
  $y0 = [int]$parts[0]; $y1 = [int]$parts[1]
  $minX = -1; $maxX = -1; $runs = ""
  $runStart = -1
  for ($y = $y0; $y -le $y1; $y++) {
    for ($x = $X0; $x -lt $X1; $x++) {
      $c = $bmp.GetPixel($x, $y)
      $r = $c.R; $g = $c.G; $b = $c.B
      $mx = [Math]::Max($r, [Math]::Max($g, $b)); $mn = [Math]::Min($r, [Math]::Min($g, $b))
      $ink = $false
      if ($Mode -eq "dark") { $ink = ($mx -lt 120 -and ($mx - $mn) -lt 60) }
      elseif ($Mode -eq "dblue") { $ink = ($b -gt ($r + 60) -and $b -gt ($g + 40) -and $r -lt 90) }
      if ($ink) {
        if ($minX -lt 0 -or $x -lt $minX) { $minX = $x }
        if ($x -gt $maxX) { $maxX = $x }
      }
    }
  }
  Write-Output ("ROW {0}..{1} mode={2} minX={3} maxX={4}" -f $y0, $y1, $Mode, $minX, $maxX)
}
$bmp.Dispose()

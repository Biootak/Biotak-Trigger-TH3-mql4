param([string]$Path)
Add-Type -AssemblyName System.Drawing
$bmp = [System.Drawing.Bitmap]::FromFile($Path)
Write-Output ("SIZE {0}x{1}" -f $bmp.Width, $bmp.Height)
$pts = @(
  @(960,105),@(960,150),@(960,200),@(400,238),@(400,260),@(400,300),
  @(960,400),@(960,500),@(960,620),@(400,650),@(400,700),@(960,850),
  @(20,300),@(1900,300),@(1900,105),@(5,600)
)
foreach ($p in $pts) {
  $c = $bmp.GetPixel($p[0], $p[1])
  Write-Output ("PX {0},{1} = {2},{3},{4}" -f $p[0], $p[1], $c.R, $c.G, $c.B)
}
$bmp.Dispose()

<# build-rc-bridge.ps1 | P-UI-108 - rebuilds Libraries/BiotakRCBlock.dll with tcc #>
param(
  [string]$WorkDir = ""
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)   # repo root (tools\rc-bridge)
if($WorkDir -eq "") { $WorkDir = $Root }
$src = Join-Path $PSScriptRoot "rc-bridge-c.c"
$outDir = Join-Path $Root "Libraries"
$out = Join-Path $outDir "BiotakRCBlock.dll"
if(!(Test-Path $src)) { Write-Output "MISSING SRC: $src"; exit 1 }
if(!(Test-Path $outDir)) { New-Item -ItemType Directory $outDir | Out-Null }
$tcc = Join-Path $env:TEMP "tcc\tcc\tcc.exe"
if(!(Test-Path $tcc)) {
  Invoke-WebRequest -Uri "https://download.savannah.gnu.org/releases/tinycc/tcc-0.9.27-win32-bin.zip" -OutFile (Join-Path $env:TEMP "tcc.zip")
  Expand-Archive (Join-Path $env:TEMP "tcc.zip") -DestinationPath (Join-Path $env:TEMP "tcc") -Force
}
& $tcc -shared -o $out $src -luser32
if(!(Test-Path $out)) { Write-Output "BUILD-FAILED"; exit 1 }
Write-Output ("BUILT: " + $out + " (" + (Get-Item $out).Length + " bytes)")
# Deploy to the live terminal so the next attach loads it.
$term = Join-Path $env:APPDATA "MetaQuotes\Terminal\0727F3F88B5F0FE006962B330B91FF37\MQL4\Libraries\BiotakRCBlock.dll"
Copy-Item $out $term -Force
Write-Output ("DEPLOYED: " + $term)

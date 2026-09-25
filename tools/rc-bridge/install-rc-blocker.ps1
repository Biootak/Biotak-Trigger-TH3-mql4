<# install-rc-blocker.ps1 | P-UI-107 STEP 1 - builds tools/rc-bridge/rc-blocker.exe #>
param(
  [string]$WorkDir = ""
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)   # repo root (tools\rc-bridge)
if($WorkDir -eq "") { $WorkDir = $Root }
$src = Join-Path $PSScriptRoot "rc-blocker-src.cs"
$exe = Join-Path $PSScriptRoot "rc-blocker.exe"
if(!(Test-Path $src)) { Write-Output "MISSING SRC: $src"; exit 1 }
Add-Type -OutputAssembly $exe -OutputType WindowsApplication `
  -ReferencedAssemblies @("System.Windows.Forms") `
  -TypeDefinition ([IO.File]::ReadAllText($src))
Write-Output ("BUILT: " + $exe)

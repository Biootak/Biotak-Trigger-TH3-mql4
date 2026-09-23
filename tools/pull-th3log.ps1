<# P-TH3-LOG2: pull the indicator's own verdict CSVs into the repo.
   The indicator appends TH3LOG lines to MQL4/Files/TH3LOG_<sym>_<tf>.csv
   (the sandbox answers nowhere else); this copies them to th3logs/ where
   tools/th3_log_collect.py reads them - no Experts copy-paste. #>
param([string]$Dest = "")
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($Dest -eq "") { $Dest = Join-Path $repo "th3logs" }
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
$terms = Get-ChildItem -LiteralPath (Join-Path $env:APPDATA "MetaQuotes\Terminal") -Directory -ErrorAction SilentlyContinue
$n = 0
foreach ($t in $terms) {
    $files = Join-Path $t.FullName "MQL4\Files\TH3LOG_*.csv"
    foreach ($f in (Get-ChildItem -Path $files -ErrorAction SilentlyContinue)) {
        Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $Dest $f.Name) -Force
        $n++
    }
}
Write-Output "pulled $n TH3LOG file(s) into $Dest"

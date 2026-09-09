# tools/fetch_tradeplan_log.ps1
# Reads [TRADEPLAN] lines from the latest MT4 Experts log and writes
# build-logs/tradeplan-latest.log — readable by the AI with read_file.
#
# Run after MT4 has had a few seconds to fire the tick:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools/fetch_tradeplan_log.ps1

$mql4Dir = "$env:APPDATA\MetaQuotes\Terminal\A1660DA4CB596E740BE3B3233E577E1B\MQL4"
$logsDir = Join-Path $mql4Dir "Logs"
$outFile  = Join-Path $PSScriptRoot "..\build-logs\tradeplan-latest.log"

# Find the most-recently written log file
$latest = Get-ChildItem $logsDir -Filter "*.log" -ErrorAction Stop |
          Sort-Object LastWriteTime -Descending |
          Select-Object -First 1

if (-not $latest) { Write-Host "No log file found in $logsDir"; exit 1 }

Write-Host "Reading: $($latest.FullName)  ($($latest.LastWriteTime))"

# Read with Unicode first (MT4 default), fall back to UTF8/Default
$lines = Get-Content $latest.FullName -Encoding Unicode -ErrorAction SilentlyContinue
if (-not $lines) { $lines = Get-Content $latest.FullName -ErrorAction SilentlyContinue }

# Filter only [TRADEPLAN] lines
$tp = $lines | Where-Object { $_ -match '\[TRADEPLAN\]' }

if (-not $tp) {
    Write-Host "No [TRADEPLAN] entries found yet. Make sure the indicator is attached and running."
    "[No TRADEPLAN entries found in $($latest.Name) at $(Get-Date)]" | Set-Content $outFile -Encoding UTF8
    exit 0
}

# Write clean readable output
$header = "# Captured from: $($latest.FullName)`n# At: $(Get-Date)`n# Lines: $($tp.Count)`n"
$header | Set-Content $outFile -Encoding UTF8
$tp | Add-Content $outFile -Encoding UTF8

Write-Host "Written $($tp.Count) lines -> build-logs/tradeplan-latest.log"
Write-Host ""
$tp | Select-Object -Last 30 | ForEach-Object { Write-Host $_ }

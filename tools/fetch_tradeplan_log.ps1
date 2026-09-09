# tools/fetch_tradeplan_log.ps1
# Reads [TRADEPLAN] lines from the latest MT4 Experts log and writes
# build-logs/tradeplan-latest.log — readable by the AI with read_file.
#
# MT4 writes Logs\*.log as UTF-16 LE with BOM and keeps the file locked
# while running. We use FileShare.ReadWrite + BOM-aware StreamReader.
#
# Run after MT4 has had a few seconds to fire the tick:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools/fetch_tradeplan_log.ps1

$mql4Dir = "$env:APPDATA\MetaQuotes\Terminal\A1660DA4CB596E740BE3B3233E577E1B\MQL4"
$logsDir = Join-Path $mql4Dir "Logs"
$outFile  = Join-Path $PSScriptRoot "..\build-logs\tradeplan-latest.log"

# Ensure output dir exists
$null = New-Item -ItemType Directory -Force -Path (Split-Path $outFile)

# Find the most-recently written log file
$latest = Get-ChildItem $logsDir -Filter "*.log" -ErrorAction Stop |
          Sort-Object LastWriteTime -Descending |
          Select-Object -First 1

if (-not $latest) { Write-Host "No log file found in $logsDir"; exit 1 }

Write-Host "Reading: $($latest.FullName)  ($($latest.LastWriteTime))"

# Read with FileShare.ReadWrite so we can read even while MT4 has the file open.
# Use detectEncodingFromByteOrderMarks=true so UTF-16 LE BOM is handled automatically.
$text = $null
try {
    $stream = [System.IO.File]::Open(
        $latest.FullName,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite
    )
    $reader = New-Object System.IO.StreamReader($stream, $true)   # detectBOM = true
    $text   = $reader.ReadToEnd()
    $reader.Close()
    $stream.Close()
} catch {
    Write-Host "Stream read failed: $_"
    Write-Host "Falling back to Get-Content..."
    try {
        $text = (Get-Content $latest.FullName -Encoding Unicode -Raw -ErrorAction Stop)
    } catch {
        Write-Host "Both read methods failed: $_"; exit 1
    }
}

if (-not $text) { Write-Host "Log file is empty."; exit 1 }

$lines = $text -split "`r?`n"
Write-Host "Total log lines: $($lines.Count)"

# Filter only [TRADEPLAN] lines
$tp = $lines | Where-Object { $_ -match '\[TRADEPLAN\]' }

if (-not $tp) {
    Write-Host ""
    Write-Host "No [TRADEPLAN] entries found yet."
    Write-Host "  -> Make sure the indicator is attached and running on a chart."
    Write-Host "  -> The log fires once per 2s when values change."
    Write-Host ""
    Write-Host "--- Last 30 non-empty lines (for diagnosis) ---"
    $lines | Where-Object { $_ -match '\S' } | Select-Object -Last 30 | ForEach-Object { Write-Host $_ }
    "[No TRADEPLAN entries found in $($latest.Name) at $(Get-Date)]" | Set-Content $outFile -Encoding UTF8
    exit 0
}

# Write clean readable output
$header  = "# Captured from: $($latest.FullName)`n"
$header += "# At: $(Get-Date)`n"
$header += "# Lines: $($tp.Count)`n"
$header += "# Log file modified: $($latest.LastWriteTime)`n"
$header | Set-Content $outFile -Encoding UTF8
$tp | Add-Content $outFile -Encoding UTF8

Write-Host ""
Write-Host "Written $($tp.Count) [TRADEPLAN] lines -> build-logs/tradeplan-latest.log"
Write-Host ""
$tp | Select-Object -Last 40 | ForEach-Object { Write-Host $_ }

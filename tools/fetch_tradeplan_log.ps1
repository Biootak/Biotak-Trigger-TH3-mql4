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

# Filter [TRADEPLAN] and [SNAP] lines
$tp   = $lines | Where-Object { $_ -match '\[TRADEPLAN\]' }
$snap = $lines | Where-Object { $_ -match '\[SNAP\]' }

if (-not $tp -and -not $snap) {
    Write-Host ""
    Write-Host "No [TRADEPLAN] or [SNAP] entries found yet."
    Write-Host "  -> Make sure the indicator is attached and running on a chart."
    Write-Host "  -> [SNAP] fires every 10 s when values change."
    Write-Host ""
    Write-Host "--- Last 30 non-empty lines (for diagnosis) ---"
    $lines | Where-Object { $_ -match '\S' } | Select-Object -Last 30 | ForEach-Object { Write-Host $_ }
    "[No TRADEPLAN entries found in $($latest.Name) at $(Get-Date)]" | Set-Content $outFile -Encoding UTF8
    exit 0
}

# Write clean readable output — SNAP snapshots first, then per-chart rows
$header  = "# Captured from: $($latest.FullName)`n"
$header += "# At: $(Get-Date)`n"
$header += "# Log file modified: $($latest.LastWriteTime)`n"
$header += "# [SNAP] lines: $($snap.Count)  [TRADEPLAN] lines: $($tp.Count)`n"
$header | Set-Content $outFile -Encoding UTF8

if ($snap.Count -gt 0) {
    ""                             | Add-Content $outFile -Encoding UTF8
    "# === 8-TF SNAPSHOTS ===" | Add-Content $outFile -Encoding UTF8
    # Keep last 3 complete snapshots (each is ~11 lines)
    $snap | Select-Object -Last 33 | Add-Content $outFile -Encoding UTF8
}
if ($tp.Count -gt 0) {
    ""                             | Add-Content $outFile -Encoding UTF8
    "# === PER-CHART ROWS ===" | Add-Content $outFile -Encoding UTF8
    $tp | Select-Object -Last 48 | Add-Content $outFile -Encoding UTF8
}

Write-Host ""
Write-Host "[SNAP] lines: $($snap.Count)   [TRADEPLAN] lines: $($tp.Count)"
Write-Host "Written -> build-logs/tradeplan-latest.log"
Write-Host ""
# Show latest snapshot to stdout
if ($snap.Count -gt 0) {
    Write-Host "--- Latest 8-TF snapshot ---"
    $snap | Select-Object -Last 11 | ForEach-Object { Write-Host $_ }
} else {
    Write-Host "--- Last 20 TRADEPLAN rows (no snapshot yet) ---"
    $tp | Select-Object -Last 20 | ForEach-Object { Write-Host $_ }
}

# tools/read_tradeplan_log.ps1
# Copies tradeplan_log.txt from the MT4 terminal's MQL4\Files\ directory
# into the repo root so the AI can read it with read_file.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools/read_tradeplan_log.ps1
#
# After running, the AI reads: tradeplan_log.txt (repo root)

$ErrorActionPreference = "Stop"

# ── locate all known MT4 terminal roots ──────────────────────────────────────
$mqRoot = Join-Path $env:APPDATA "MetaQuotes\Terminal"
$terminalDirs = Get-ChildItem $mqRoot -Directory -ErrorAction SilentlyContinue

$candidates = @()
foreach ($td in $terminalDirs) {
    $f = Join-Path $td.FullName "MQL4\Files\tradeplan_log.txt"
    if (Test-Path $f) {
        $candidates += [PSCustomObject]@{
            Path         = $f
            LastModified = (Get-Item $f).LastWriteTime
        }
    }
}

if ($candidates.Count -eq 0) {
    Write-Host "tradeplan_log.txt not found in any MT4 terminal MQL4\Files\ folder."
    Write-Host "Make sure the indicator is attached and has run at least one tick."
    exit 1
}

# pick the most-recently modified copy
$best = ($candidates | Sort-Object LastModified -Descending)[0]
Write-Host "Source : $($best.Path)"
Write-Host "Modified: $($best.LastModified)"

$dest = Join-Path $PSScriptRoot "..\tradeplan_log.txt"
Copy-Item -Path $best.Path -Destination $dest -Force

Write-Host "Copied  → tradeplan_log.txt (repo root)"
Write-Host ""
Write-Host "Last 40 lines:"
Write-Host "──────────────────────────────────────────"
Get-Content $dest -Encoding UTF8 -ErrorAction SilentlyContinue |
    Select-Object -Last 40 |
    ForEach-Object { Write-Host $_ }

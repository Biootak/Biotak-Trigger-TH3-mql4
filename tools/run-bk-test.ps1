# Run one Base Knot harness inside MetaTrader 4 and print its verdict.
#
# WHY: a harness asserts numbers a green compile cannot - it drives the PRODUCTION owners and
# compares them to literals. A compile only proves the names resolve. This script is what makes
# the numbers real: it drops the ex4 into the instance's Scripts\, writes MT4's "Configuration
# at Startup" file (one extra chart, never saved to the profile), launches the terminal, waits
# for a NEW flushed "<TAG> DONE" line and prints every line this run wrote.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-bk-test.ps1 `
#       -Harness Biotak_BaseKnot_Shot_Test -Tag BKSHOT
#
#   ... -Symbol XAUUSD -Period M5 -TimeoutSec 240 -KeepTerminal
#
# Exit code: 0 = the run finished and no FAIL line, 1 = a FAIL line (or the run never finished).
#
# The baseline count is the whole trick: MT4 appends to the day's log, so a PREVIOUS run's DONE
# line is already in the file. "This run finished" is a fact only against a count taken before
# the launch. The printed slice starts at this run's own marker, so an earlier run's PASS lines
# can never be counted as this run's.

param(
    [Parameter(Mandatory = $true)][string]$Harness,
    [Parameter(Mandatory = $true)][string]$Tag,
    [string]$Header = "",
    [string]$DataDir = "A1660DA4CB596E740BE3B3233E577E1B",
    [string]$Symbol = "EURUSD",
    [string]$Period = "H1",
    [int]$TimeoutSec = 180,
    [switch]$KeepTerminal
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$ex4 = Join-Path $root "tests\$Harness.ex4"
if (-not (Test-Path -LiteralPath $ex4)) {
    throw "missing $ex4 - build it first: compile-th3.ps1 -SourceFile tests\$Harness.mq4"
}

$data = Join-Path $env:APPDATA "MetaQuotes\Terminal\$DataDir"
$mql4 = Join-Path $data "MQL4"
if (-not (Test-Path -LiteralPath $mql4)) { throw "no MQL4 folder at $mql4" }
$install = "C:\Program Files (x86)\AMarkets - MetaTrader 4"
$terminal = Join-Path $install "terminal.exe"
if (-not (Test-Path -LiteralPath $terminal)) { throw "no terminal.exe at $terminal" }

$scripts = Join-Path $mql4 "Scripts"
if (-not (Test-Path -LiteralPath $scripts)) { New-Item -ItemType Directory -Path $scripts -Force | Out-Null }
Copy-Item -LiteralPath $ex4 -Destination (Join-Path $scripts "$Harness.ex4") -Force

# THE SINGLE-INSTANCE TRAP. MT4 allows one process per data folder: launching terminal.exe
# with an ini while the user's terminal is already up just ACTIVATES that window and runs
# nothing, so the run looks like a hang and the harness looks broken. Measured 2026-10-27:
# a live XAUUSD H1 terminal made this script wait the full 180 s and print nothing.
$busy = @(Get-Process terminal -ErrorAction SilentlyContinue)
if ($busy.Count -gt 0) {
    $titles = ($busy | ForEach-Object { $_.MainWindowTitle }) -join " | "
    throw "MetaTrader is already running ($($busy[0].Id): $titles). Close it first - MT4 runs one process per data folder and an ini launch would be a no-op."
}

$logDir = Join-Path $mql4 "Logs"
$donePattern = "\[$Tag\] DONE"
$markPattern = if ($Header -ne "") { $Header } else { "\[$Tag\] START" }

function Get-NewestLog {
    $l = @(Get-ChildItem -LiteralPath $logDir -Filter *.log -File -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    if ($l.Count -gt 0) { return $l[0] } else { return $null }
}
function Count-Done([string]$path) {
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { return 0 }
    return @(Select-String -LiteralPath $path -Pattern $donePattern -ErrorAction SilentlyContinue).Count
}

$baseLog = Get-NewestLog
$basePath = if ($baseLog) { $baseLog.FullName } else { "" }
$baseline = Count-Done $basePath

$ini = Join-Path $root "build-logs\bk-run-$Tag.ini"
$lines = @("; run-bk-test.ps1 - MT4 Configuration at Startup (one extra chart, not saved)",
           "Symbol=$Symbol",
           "Period=$Period",
           "Script=$Harness",
           "ExpertsEnable=true")
Set-Content -LiteralPath $ini -Value $lines -Encoding ASCII

Write-Host "  harness: $scripts\$Harness.ex4"
Write-Host "  config:  $ini  (Symbol=$Symbol Period=$Period)"
$proc = Start-Process -FilePath $terminal -ArgumentList "`"$ini`"" -PassThru
Write-Host "  launched terminal (pid $($proc.Id)); waiting up to ${TimeoutSec}s for [$Tag] DONE ..."

$deadline = (Get-Date).AddSeconds($TimeoutSec)
$hit = $false
while ((Get-Date) -lt $deadline) {
    $log = Get-NewestLog
    if ($log) {
        if ($log.FullName -ne $basePath) { $basePath = $log.FullName; $baseline = 0 }
        if ((Count-Done $log.FullName) -gt $baseline) { $hit = $true; break }
    }
    Start-Sleep -Milliseconds 500
}

$log = Get-NewestLog
$mine = @()
if ($log) {
    $all = @(Get-Content -LiteralPath $log.FullName -ErrorAction SilentlyContinue)
    $start = 0
    for ($i = 0; $i -lt $all.Count; $i++) {
        if ($all[$i] -match $markPattern) { $start = $i }
    }
    if ($all.Count -gt 0) {
        $mine = @($all[$start..($all.Count - 1)] | Where-Object { $_ -match "\[$Tag\]" })
    }
    if ($mine.Count -gt 0) { $mine | ForEach-Object { Write-Host $_ } }
    if (-not $hit) { Write-Host "  [FAIL] no [$Tag] DONE within ${TimeoutSec}s - last log: $($log.FullName)" }
}

if (-not $KeepTerminal) {
    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}

if (-not $hit) { exit 1 }
$fails = @($mine | Where-Object { $_ -match "\[$Tag\] FAIL" }).Count
$pass  = @($mine | Where-Object { $_ -match "\[$Tag\] PASS" }).Count
Write-Host ""
Write-Host "  RESULT: $pass passed, $fails failed"
exit ($(if ($fails -eq 0) { 0 } else { 1 }))

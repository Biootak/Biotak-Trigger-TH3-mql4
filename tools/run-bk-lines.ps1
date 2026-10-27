# Run tests\Biotak_BaseKnot_Lines_Test.ex4 inside MetaTrader 4 and print its verdict.
#
# WHY: the harness asserts the four knot types x three components (entry / stop / TP1..3)
# through the PRODUCTION owners. A green compile proves only that the names resolve; this
# script is what makes the numbers real - it drops the ex4 into the instance's Scripts\,
# writes MT4's "Configuration at Startup" file (one extra chart, never saved to the profile),
# launches the terminal, waits for the flushed `[BKLINES] DONE` line and prints every
# [BKLINES] line it wrote.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-bk-lines.ps1
#   ... -DataDir <terminal id> -Symbol EURUSD -Period H1 -TimeoutSec 180
#
# Exit code: 0 = every assertion passed, 1 = a FAIL line (or the run never finished).

param(
    [string]$DataDir = "A1660DA4CB596E740BE3B3233E577E1B",
    [string]$Symbol = "EURUSD",
    [string]$Period = "H1",
    [int]$TimeoutSec = 180,
    [switch]$KeepTerminal
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$harness = "Biotak_BaseKnot_Lines_Test"
$ex4 = Join-Path $root "tests\$harness.ex4"
if (-not (Test-Path -LiteralPath $ex4)) {
    throw "missing $ex4 - build it first: compile-th3.ps1 -SourceFile tests\$harness.mq4"
}

$data = Join-Path $env:APPDATA "MetaQuotes\Terminal\$DataDir"
$mql4 = Join-Path $data "MQL4"
if (-not (Test-Path -LiteralPath $mql4)) { throw "no MQL4 folder at $mql4" }
$install = "C:\Program Files (x86)\AMarkets - MetaTrader 4"
$terminal = Join-Path $install "terminal.exe"
if (-not (Test-Path -LiteralPath $terminal)) { throw "no terminal.exe at $terminal" }

$scripts = Join-Path $mql4 "Scripts"
if (-not (Test-Path -LiteralPath $scripts)) { New-Item -ItemType Directory -Path $scripts -Force | Out-Null }
Copy-Item -LiteralPath $ex4 -Destination (Join-Path $scripts "$harness.ex4") -Force

$logDir = Join-Path $mql4 "Logs"

function Get-NewestLog {
    $l = @(Get-ChildItem -LiteralPath $logDir -Filter *.log -File -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    if ($l.Count -gt 0) { return $l[0] } else { return $null }
}
function Count-Done([string]$path) {
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { return 0 }
    return @(Select-String -LiteralPath $path -Pattern "\[BKLINES\] DONE" -ErrorAction SilentlyContinue).Count
}

# MT4 appends to the day's log, so a PREVIOUS run's DONE line is already in the file.
# The baseline count is what makes "this run finished" a fact instead of a guess.
$baseLog = Get-NewestLog
$basePath = if ($baseLog) { $baseLog.FullName } else { "" }
$baseline = Count-Done $basePath

$ini = Join-Path $root "build-logs\bk-lines.ini"
$lines = @("; run-bk-lines.ps1 - MT4 Configuration at Startup (one extra chart, not saved)",
           "Symbol=$Symbol",
           "Period=$Period",
           "Script=$harness",
           "ExpertsEnable=true")
Set-Content -LiteralPath $ini -Value $lines -Encoding ASCII

Write-Host "  harness: $scripts\$harness.ex4"
Write-Host "  config:  $ini  (Symbol=$Symbol Period=$Period)"
$proc = Start-Process -FilePath $terminal -ArgumentList "`"$ini`"" -PassThru
Write-Host "  launched terminal (pid $($proc.Id)); waiting up to ${TimeoutSec}s for [BKLINES] DONE ..."

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
    # keep only THIS run: the last header line onward
    $start = 0
    for ($i = 0; $i -lt $all.Count; $i++) {
        if ($all[$i] -match "four types x three components") { $start = $i }
    }
    $mine = @()
    if ($all.Count -gt 0) {
        $mine = @($all[$start..($all.Count - 1)] | Where-Object { $_ -match "\[BKLINES\]" })
    }
    if ($mine.Count -gt 0) { $mine | ForEach-Object { Write-Host $_ } }
    if (-not $hit) { Write-Host "  [FAIL] no [BKLINES] DONE within ${TimeoutSec}s - last log: $($log.FullName)" }
}

if (-not $KeepTerminal) {
    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}

if (-not $hit) { exit 1 }
$fails = @($mine | Where-Object { $_ -match "\[BKLINES\] FAIL" }).Count
$pass  = @($mine | Where-Object { $_ -match "\[BKLINES\] PASS" }).Count
Write-Host ""
Write-Host "  RESULT: $pass passed, $fails failed"
exit ($(if ($fails -eq 0) { 0 } else { 1 }))

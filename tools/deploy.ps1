<#
.SYNOPSIS
    Biotak Trigger TH3 — one-command icon pipeline & deploy.

    Guarantees that whenever icons change, EVERY copy lands in its place:
      1. Regenerate all 42 icons  -> Files/Icons/  (tools/gen-th3-icons.js)
      2. Compile workspace + installed .ex4        (compile-th3.ps1 -Project all,
                                                    which first syncs Files/Icons into
                                                    EVERY MT4 terminal hosting the project)
      3. Verify: fresh .ex4, and each hosting terminal's Files/Icons matches the repo
         byte-for-byte for every BMP.

    After it finishes, MT4 still needs a reload of the indicator itself
    (remove & re-add from the chart, or restart the terminal) — the .ex4 is
    only read when the indicator is attached.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\deploy.ps1

.EXAMPLE
    # Only recompile + resync (skip icon regeneration)
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\deploy.ps1 -SkipIconRegen
#>
[CmdletBinding()]
param(
    [switch]$SkipIconRegen
)
$ErrorActionPreference = 'Stop'

$Root  = Split-Path -Parent $PSScriptRoot          # repo root (tools\..)
$Icons = Join-Path $Root 'Files\Icons'
$Ex4   = Join-Path $Root 'Biotak Trigger TH3.ex4'
$Start = Get-Date

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Biotak Trigger TH3 - icon deploy" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# ---------------------------------------------------------------- 1/3 icons
if ($SkipIconRegen) {
    Write-Host "`n[1/3] Skipping icon regeneration (-SkipIconRegen)" -ForegroundColor DarkCyan
} else {
    Write-Host "`n[1/3] Regenerating icons (tools/gen-th3-icons.js) -> Files/Icons" -ForegroundColor DarkCyan
    Push-Location $Root
    try {
        & node (Join-Path $PSScriptRoot 'gen-th3-icons.js')
        if ($LASTEXITCODE -ne 0) { throw "Icon generation failed (node exit $LASTEXITCODE)" }
    } finally { Pop-Location }
    Write-Host "      OK - icons regenerated." -ForegroundColor Green
}

# ---------------------------------------------------------------- 2/3 compile
Write-Host "`n[2/3] Compiling workspace + installed (auto-syncs icons into every hosting terminal)" -ForegroundColor DarkCyan
Push-Location $Root
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'compile-th3.ps1') -Project all
    if ($LASTEXITCODE -ne 0) { Write-Warning "compile-th3.ps1 exited with code $LASTEXITCODE - check the log above." }
} finally { Pop-Location }

# ---------------------------------------------------------------- 3/3 verify
Write-Host "`n[3/3] Verifying deploy" -ForegroundColor DarkCyan

# 3a) ex4 freshness
if (Test-Path $Ex4) {
    $ex4Age = (Get-Date) - (Get-Item $Ex4).LastWriteTime
    if ($ex4Age.TotalMinutes -lt 10) {
        Write-Host "      ex4 fresh : $Ex4 ($((Get-Item $Ex4).LastWriteTime.ToString('HH:mm:ss')))" -ForegroundColor Green
    } else {
        Write-Warning "      ex4 NOT freshly built (last write $((Get-Item $Ex4).LastWriteTime)) - did the compile pass?"
    }
} else {
    Write-Warning "      ex4 missing: $Ex4"
}

# 3b) terminal icon folders byte-identical to the repo
$repoHashes = @{}
Get-ChildItem -Path $Icons -Filter '*.bmp' | ForEach-Object {
    $repoHashes[$_.Name] = (Get-FileHash $_.FullName -Algorithm MD5).Hash
}

$termRoot = Join-Path $env:APPDATA 'MetaQuotes\Terminal'
$hosted = @()
if (Test-Path $termRoot) {
    Get-ChildItem -Path $termRoot -Directory | ForEach-Object {
        $probe = Join-Path $_.FullName 'MQL4\Indicators\BiotakProject'
        if (Test-Path $probe) { $hosted += Join-Path $_.FullName 'MQL4' }
    }
}
if ($hosted.Count -eq 0) {
    Write-Host "      no hosting terminal found (Indicators\BiotakProject) - nothing to sync." -ForegroundColor Yellow
} else {
    foreach ($mql4 in $hosted) {
        $dst = Join-Path $mql4 'Files\Icons'
        $ok  = $true
        $diff = @()
        foreach ($name in $repoHashes.Keys) {
            $t = Join-Path $dst $name
            if (-not (Test-Path $t)) { $ok = $false; $diff += "$name (missing)" }
            elseif ((Get-FileHash $t -Algorithm MD5).Hash -ne $repoHashes[$name]) { $ok = $false; $diff += $name }
        }
        if ($ok) {
            Write-Host "      terminal OK : $dst ($($repoHashes.Count) BMPs identical)" -ForegroundColor Green
        } else {
            Write-Warning "      terminal STALE: $dst -> differs on: $($diff -join ', ')"
        }
    }
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " Deploy finished in $([math]::Round(((Get-Date)-$Start).TotalSeconds,1))s" -ForegroundColor Cyan
Write-Host " Next (required): in MetaTrader remove 'Biotak Trigger TH3' from the chart" -ForegroundColor Yellow
Write-Host " and re-add it (or restart the terminal) - MT4 reads the .ex4 only at attach time." -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

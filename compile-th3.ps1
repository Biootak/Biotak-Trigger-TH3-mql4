<#
.SYNOPSIS
    MQL4 Compiler Script for MetaTrader 4
    Compiles .mq4 files using metaeditor.exe from the command line.

.DESCRIPTION
    This script provides easy compilation of MQL4 indicators/EAs/scripts
    without needing to press Compile in MetaEditor.
    
    It supports:
    - Compiling this workspace project
    - Compiling installed projects (optional)
    - Compiling any arbitrary .mq4 file
    - Colored output with error/warning highlighting
    - Automatic error extraction and summary
    - Automatic MetaEditor/MQL4 path detection

.NOTES
    Optional environment variables:
    - MT4_METAEDITOR : full path to metaeditor.exe
    - MT4_MQL4_DIR   : full path to MQL4 folder

.PARAMETER Project
    Which project to compile:
    - "workspace" (default): compile current project file in this repository
    - "installed": compile installed indicator path
    - "all": compile all of the above

.PARAMETER SourceFile
    Optional: Full path to a specific .mq4 file to compile.
    Overrides the -Project parameter.

.EXAMPLE
    .\compile-th3.ps1
    # Compiles the workspace project (default)

.EXAMPLE
    .\compile-th3.ps1 -Project all
    # Compiles workspace + installed

.EXAMPLE
    .\compile-th3.ps1 -SourceFile "C:\path\to\file.mq4"
    # Compiles a specific file

.EXAMPLE
    .\compile-th3.ps1 -MetaEditorPath "C:\MT4\metaeditor.exe"
    # Compiles using a specific metaeditor path
#>

param(
    [ValidateSet("workspace", "installed", "all")]
    [string]$Project = "workspace",
    
    [string]$SourceFile = "",

    [bool]$PrintLog = $true,

    [ValidateRange(0, 5000)]
    [int]$LogTailLines = 120,

    [bool]$IncludeRuntimeLogs = $true,

    [ValidateRange(0, 5000)]
    [int]$RuntimeLogTailLines = 80,

    [bool]$IncrementalRuntimeLogs = $true,

    [bool]$EnableLogCleanup = $true,

    [ValidateRange(1, 365)]
    [int]$LogRetentionDays = 14,

    [ValidateRange(10, 5000)]
    [int]$MaxBuildLogs = 400,

    [bool]$WatchRuntimeLogs = $false,

    [ValidateRange(5, 3600)]
    [int]$WatchSeconds = 60,

    [ValidateRange(250, 5000)]
    [int]$WatchPollMs = 1000,

    [string]$MetaEditorPath = "",

    [string]$Mql4Dir = "",

    [switch]$RestartTerminal,

    #--- P-BUILD-09 (2026-10-01) — THE INNER LOOP HAS THREE GATE MODES.
    #--- MEASURED, the whole gate layer is 1.76s of work (check-resources 269ms,
    #--- regressions 186, level-continuity 150, object-lifecycle 309, stale-state 313,
    #--- submenu 101, gear-panel 438) — so the hour a one-line fix takes is the MT4
    #--- round trip and the writing, not this. What these modes buy is honesty at the
    #--- cheapskate's price: `scoped` (default) skips a gate only when the bytes it
    #--- reads AND its own script are identical to the run that PASSED last, and it
    #--- PRINTS `[SKIP]`, so no report can claim a check it did not run. `full` runs
    #--- everything (before "done"). `-Fast` is `-Gates off` for the inner loop, and
    #--- it says so in yellow, because a green `-Fast` build proves the names resolve
    #--- and nothing else.
    [ValidateSet("scoped", "full", "off")]
    [string]$Gates = "scoped",

    [switch]$Fast,

    #--- P-BUILD-09: every tests\*.mq4 in ONE process, so the gate layer runs once
    #--- instead of once per harness (9 x ~6s of wall clock -> ~4s each + 1 gate run).
    [switch]$Tests,

    #--- P-BUILD-10 (2026-10-01) — THE REAL RENDER, ONE COMMAND. The harness
    #--- `tests/Biotak_StripShot_Test.mq4` paints the strip and ALL FOUR `Box
    #--- Settings` tabs through the real paint path and writes StripShot_<tag>.png
    #--- plus a per-object census with the TERMINAL's own rects. `-Shot` compiles it,
    #--- drops the ex4 into the instance's Scripts\, writes MT4's "Configuration at
    #--- Startup" file and prints the one command to run. With `-RestartTerminal` it
    #--- also closes MT4, launches it on that config, waits for `[STRIPSHOT] DONE:`,
    #--- collects the census + PNGs, brings the closed instances back and rebuilds
    #--- tools/before-after.html (design | sim | the terminal's own pixels).
    [switch]$Shot,
    [string]$ShotSymbol = "EURUSD",
    [string]$ShotPeriod = "H1",
    [ValidateRange(10, 600)]
    [int]$ShotTimeoutSec = 120
)

# ============================================================
# CONFIGURATION - Edit these if your paths differ
# ============================================================

$SCRIPT_ROOT    = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$DEFAULT_MT4_INSTALL = "C:\Program Files (x86)\AMarkets - MetaTrader 4"
$DEFAULT_METAEDITOR  = Join-Path $DEFAULT_MT4_INSTALL "metaeditor.exe"
$APPDATA_TERMINAL_ROOT = Join-Path $env:APPDATA "MetaQuotes\Terminal"
$PROJECT_LOG_DIR = Join-Path $SCRIPT_ROOT "build-logs"
$RUNTIME_STATE_FILE = Join-Path $PROJECT_LOG_DIR ".runtime-log-state.json"
$WORKSPACE_SOURCE = Join-Path $SCRIPT_ROOT "Biotak Trigger TH3.mq4"

# ============================================================
# FUNCTIONS
# ============================================================

function Write-Banner {
    param([string]$Text)
    $line = "=" * 60
    Write-Host ""
    Write-Host $line -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host $line -ForegroundColor Cyan
}

function Resolve-MetaEditorPath {
    param([string]$CustomPath)

    $candidates = @()

    # 1. Explicit parameter
    if ($CustomPath) {
        $candidates += $CustomPath
    }
    # 2. Environment variable
    if ($env:MT4_METAEDITOR) {
        $candidates += $env:MT4_METAEDITOR
    }
    # 3. Default install path
    $candidates += $DEFAULT_METAEDITOR

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    # 4. Search Program Files directories for MetaTrader 4 installations
    $programRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ -and (Test-Path $_) }
    foreach ($root in $programRoots) {
        $dirs = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue
        foreach ($dir in $dirs) {
            if ($dir.Name -like "*MetaTrader 4*" -or $dir.Name -like "*MT4*") {
                $editor = Join-Path $dir.FullName "metaeditor.exe"
                if (Test-Path -LiteralPath $editor -PathType Leaf) {
                    return $editor
                }
            }
        }
    }

    # 5. Search common broker-named MT4 installations in Program Files
    foreach ($root in $programRoots) {
        $dirs = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue
        foreach ($dir in $dirs) {
            $editor = Join-Path $dir.FullName "metaeditor.exe"
            if (Test-Path -LiteralPath $editor -PathType Leaf) {
                # Verify it's an MT4 metaeditor (32-bit, not metaeditor64)
                return $editor
            }
        }
    }

    # 6. Search Desktop and common locations for portable installations
    $extraPaths = @(
        (Join-Path $env:USERPROFILE "Desktop"),
        (Join-Path $env:USERPROFILE "Downloads"),
        "D:\",
        "E:\"
    )
    foreach ($searchRoot in $extraPaths) {
        if (-not (Test-Path -LiteralPath $searchRoot -ErrorAction SilentlyContinue)) {
            continue
        }
        $found = Get-ChildItem -Path $searchRoot -Filter "metaeditor.exe" -Recurse -Depth 4 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            return $found.FullName
        }
    }

    return $null
}

function Resolve-Mql4Directory {
    param([string]$CustomPath)

    function Normalize-Mql4Path {
        param([string]$PathCandidate)

        if (-not $PathCandidate) {
            return $null
        }
        if (-not (Test-Path -LiteralPath $PathCandidate -PathType Container)) {
            return $null
        }

        $leaf = Split-Path -Path $PathCandidate -Leaf
        if ($leaf -ieq "MQL4") {
            return (Resolve-Path -LiteralPath $PathCandidate).Path
        }

        $mql4Child = Join-Path $PathCandidate "MQL4"
        if (Test-Path -LiteralPath $mql4Child -PathType Container) {
            return (Resolve-Path -LiteralPath $mql4Child).Path
        }

        return $null
    }

    $candidates = @()
    if ($CustomPath) {
        $candidates += $CustomPath
    }
    if ($env:MT4_MQL4_DIR) {
        $candidates += $env:MT4_MQL4_DIR
    }

    foreach ($candidate in $candidates) {
        $normalized = Normalize-Mql4Path -PathCandidate $candidate
        if ($normalized) {
            return $normalized
        }
    }

    # Search AppData terminals
    if (Test-Path -LiteralPath $APPDATA_TERMINAL_ROOT -PathType Container) {
        $terminalDirs = Get-ChildItem -Path $APPDATA_TERMINAL_ROOT -Directory -ErrorAction SilentlyContinue
        $found = @()
        foreach ($terminalDir in $terminalDirs) {
            $mql4Path = Join-Path $terminalDir.FullName "MQL4"
            if (Test-Path -LiteralPath $mql4Path -PathType Container) {
                $found += [pscustomobject]@{
                    Path = $mql4Path
                    LastWriteTime = (Get-Item -LiteralPath $mql4Path).LastWriteTime
                }
            }
        }

        if ($found.Count -gt 0) {
            return ($found | Sort-Object LastWriteTime -Descending | Select-Object -First 1).Path
        }
    }

    return $null
}

# ---------------------------------------------------------------- helpers
function Get-IncludePath {
    param(
        [string]$SourcePath,
        [string]$ScriptRoot,
        [string]$ResolvedMql4Dir
    )

    if ($SourcePath.StartsWith($ScriptRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $ScriptRoot
    }

    if ($ResolvedMql4Dir -and $SourcePath.StartsWith($ResolvedMql4Dir, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $ResolvedMql4Dir
    }

    return (Split-Path -Parent $SourcePath)
}

function Wait-ForFile {
    param(
        [string]$Path,
        [int]$TimeoutMs = 10000,
        [int]$IntervalMs = 250
    )

    $elapsed = 0
    while ($elapsed -lt $TimeoutMs) {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            return $true
        }
        Start-Sleep -Milliseconds $IntervalMs
        $elapsed += $IntervalMs
    }

    return $false
}

function Read-LogContent {
    param([string]$Path)

    $encodings = @("Unicode", "UTF8", "Default")
    foreach ($encoding in $encodings) {
        $content = Get-Content -LiteralPath $Path -Encoding $encoding -ErrorAction SilentlyContinue
        if ($content -and $content.Count -gt 0) {
            return $content
        }
    }

    return (Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)
}

function Resolve-TerminalRoot {
    param([string]$ResolvedMql4Dir)

    if (-not $ResolvedMql4Dir) {
        return $null
    }

    $mql4Folder = Get-Item -LiteralPath $ResolvedMql4Dir -ErrorAction SilentlyContinue
    if (-not $mql4Folder -or -not $mql4Folder.Directory) {
        return $null
    }

    return $mql4Folder.Directory.FullName
}

function Get-LatestLogFile {
    param([string]$DirPath)

    if (-not $DirPath -or -not (Test-Path -LiteralPath $DirPath -PathType Container)) {
        return $null
    }

    return Get-ChildItem -LiteralPath $DirPath -File -Filter "*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Append-RuntimeLogs {
    param(
        [string]$CompileLogPath,
        [string]$ResolvedMql4Dir,
        [string]$TerminalRoot,
        [int]$TailLines,
        [bool]$PrintToConsole,
        [bool]$UseIncremental,
        [hashtable]$State
    )

    $expertsDir = ""
    if ($ResolvedMql4Dir) {
        $expertsDir = Join-Path $ResolvedMql4Dir "Logs"
    }

    $journalDir = ""
    if ($TerminalRoot) {
        $journalDir = Join-Path $TerminalRoot "logs"
    }

    $expertsLog = Get-LatestLogFile -DirPath $expertsDir
    $journalLog = Get-LatestLogFile -DirPath $journalDir

    $runtimeSources = @()
    if ($expertsLog) {
        $runtimeSources += [pscustomobject]@{ Type = "Experts"; File = $expertsLog }
    }
    if ($journalLog) {
        $runtimeSources += [pscustomobject]@{ Type = "Journal"; File = $journalLog }
    }

    if ($runtimeSources.Count -eq 0) {
        Add-Content -LiteralPath $CompileLogPath -Value "`r`n==== RUNTIME LOG SNAPSHOT ====`r`nNo runtime logs found.`r`n" -Encoding UTF8
        if ($PrintToConsole) {
            Write-Host "  Runtime logs: none found (Experts/Journal)." -ForegroundColor Yellow
        }
        return
    }

    Add-Content -LiteralPath $CompileLogPath -Value "`r`n==== RUNTIME LOG SNAPSHOT ====" -Encoding UTF8

    foreach ($src in $runtimeSources) {
        $content = Read-LogContent -Path $src.File.FullName
        if (-not $content) {
            continue
        }

        $stateKey = ("{0}|{1}" -f $src.Type, $src.File.FullName)
        $tail = @()

        if ($UseIncremental) {
            $previousLineCount = 0
            if ($State.ContainsKey($stateKey)) {
                $previousLineCount = [int]$State[$stateKey]
            }

            $currentLineCount = [int]$content.Count
            if ($previousLineCount -lt $currentLineCount) {
                $tail = $content | Select-Object -Skip $previousLineCount
            }
            elseif ($previousLineCount -gt $currentLineCount) {
                # Log rotated or truncated
                $tail = if ($TailLines -gt 0) { $content | Select-Object -Last $TailLines } else { $content }
            }
            else {
                $tail = @()
            }

            $State[$stateKey] = $currentLineCount
        }
        else {
            $tail = if ($TailLines -gt 0) { $content | Select-Object -Last $TailLines } else { $content }
        }

        $header = "---- $($src.Type) | File: $($src.File.FullName) | LastWrite: $($src.File.LastWriteTime) ----"
        Add-Content -LiteralPath $CompileLogPath -Value $header -Encoding UTF8

        if ($tail.Count -gt 0) {
            Add-Content -LiteralPath $CompileLogPath -Value $tail -Encoding UTF8
        }
        else {
            Add-Content -LiteralPath $CompileLogPath -Value "(no new lines since previous snapshot)" -Encoding UTF8
        }

        Add-Content -LiteralPath $CompileLogPath -Value "" -Encoding UTF8

        if ($PrintToConsole -and $tail.Count -gt 0) {
            Write-Host "  Runtime $($src.Type): $($src.File.Name)" -ForegroundColor Cyan
            $consoleTail = $tail | Select-Object -Last ([Math]::Min(12, [Math]::Max(1, $TailLines)))
            foreach ($line in $consoleTail) {
                Write-Host "    $line" -ForegroundColor DarkGray
            }
        }
        elseif ($PrintToConsole) {
            Write-Host "  Runtime $($src.Type): no new lines since previous snapshot" -ForegroundColor DarkGray
        }
    }
}

function Load-RuntimeState {
    param([string]$StatePath)

    $state = @{}
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
        return $state
    }

    try {
        $raw = Get-Content -LiteralPath $StatePath -Raw -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $obj = $raw | ConvertFrom-Json -ErrorAction Stop
            foreach ($p in $obj.PSObject.Properties) {
                $state[$p.Name] = [int]$p.Value
            }
        }
    }
    catch {
        # ignore bad state file and rebuild fresh
    }

    return $state
}

function Save-RuntimeState {
    param(
        [string]$StatePath,
        [hashtable]$State
    )

    try {
        $json = $State | ConvertTo-Json -Depth 5
        Set-Content -LiteralPath $StatePath -Value $json -Encoding UTF8
    }
    catch {
        # do not fail compilation for state write issues
    }
}

function Cleanup-BuildLogs {
    param(
        [string]$LogDir,
        [int]$RetentionDays,
        [int]$MaxFiles,
        [string]$StateFilePath
    )

    if (-not (Test-Path -LiteralPath $LogDir -PathType Container)) {
        return
    }

    $removed = 0
    $threshold = (Get-Date).AddDays(-1 * $RetentionDays)

    $logFiles = Get-ChildItem -LiteralPath $LogDir -File -Filter "*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending

    foreach ($f in ($logFiles | Where-Object { $_.LastWriteTime -lt $threshold })) {
        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
        $removed++
    }

    $remaining = Get-ChildItem -LiteralPath $LogDir -File -Filter "*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending

    if ($remaining.Count -gt $MaxFiles) {
        $extra = $remaining | Select-Object -Skip $MaxFiles
        foreach ($f in $extra) {
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
            $removed++
        }
    }

    if ($removed -gt 0) {
        Write-Host "  Log cleanup: removed $removed old log file(s)." -ForegroundColor Gray
    }

    # prune stale runtime state keys pointing to removed files
    if (Test-Path -LiteralPath $StateFilePath -PathType Leaf) {
        $state = Load-RuntimeState -StatePath $StateFilePath
        $keysToRemove = @()
        foreach ($key in $state.Keys) {
            $parts = $key -split '\|', 2
            if ($parts.Count -eq 2) {
                $filePath = $parts[1]
                if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
                    $keysToRemove += $key
                }
            }
        }

        foreach ($k in $keysToRemove) {
            $state.Remove($k) | Out-Null
        }

        if ($keysToRemove.Count -gt 0) {
            Save-RuntimeState -StatePath $StateFilePath -State $state
        }
    }
}

function Watch-RuntimeLogs {
    param(
        [string]$ResolvedMql4Dir,
        [string]$TerminalRoot,
        [int]$DurationSeconds,
        [int]$PollMs
    )

    $expertsDir = ""
    if ($ResolvedMql4Dir) {
        $expertsDir = Join-Path $ResolvedMql4Dir "Logs"
    }

    $journalDir = ""
    if ($TerminalRoot) {
        $journalDir = Join-Path $TerminalRoot "logs"
    }

    $sources = @()
    $expertsLog = Get-LatestLogFile -DirPath $expertsDir
    if ($expertsLog) {
        $sources += [pscustomobject]@{ Type = "Experts"; Path = $expertsLog.FullName; LastCount = [int](Read-LogContent -Path $expertsLog.FullName).Count }
    }

    $journalLog = Get-LatestLogFile -DirPath $journalDir
    if ($journalLog) {
        $sources += [pscustomobject]@{ Type = "Journal"; Path = $journalLog.FullName; LastCount = [int](Read-LogContent -Path $journalLog.FullName).Count }
    }

    if ($sources.Count -eq 0) {
        Write-Host "  Watch mode: no runtime logs found (Experts/Journal)." -ForegroundColor Yellow
        return
    }

    Write-Banner "WATCH RUNTIME LOGS"
    Write-Host "  Watching for ${DurationSeconds}s (poll ${PollMs}ms)..." -ForegroundColor Cyan
    foreach ($s in $sources) {
        Write-Host "  Source $($s.Type): $($s.Path)" -ForegroundColor Gray
    }
    Write-Host ""

    $endAt = (Get-Date).AddSeconds($DurationSeconds)
    while ((Get-Date) -lt $endAt) {
        foreach ($s in $sources) {
            if (-not (Test-Path -LiteralPath $s.Path -PathType Leaf)) {
                continue
            }

            $content = Read-LogContent -Path $s.Path
            if (-not $content) {
                continue
            }

            $currentCount = [int]$content.Count
            if ($currentCount -gt $s.LastCount) {
                $newLines = $content | Select-Object -Skip $s.LastCount
                foreach ($line in $newLines) {
                    Write-Host "  [$($s.Type)] $line" -ForegroundColor DarkGray
                }
            }
            elseif ($currentCount -lt $s.LastCount) {
                # file rotated/truncated
                Write-Host "  [$($s.Type)] log rotated/truncated, re-syncing..." -ForegroundColor Yellow
            }

            $s.LastCount = $currentCount
        }

        Start-Sleep -Milliseconds $PollMs
    }

    Write-Host ""
    Write-Host "  Watch mode completed." -ForegroundColor Green
}

function Get-TerminalMql4DirsForProject {
    # Every MT4 terminal whose MQL4\Indicators exposes this repo (BiotakProject
    # is a symlink back to $SCRIPT_ROOT on this machine). Each such terminal has
    # its OWN MQL4\Files\Icons used by MetaEditor when compiling the project.
    $out = @()
    $root = Join-Path $env:APPDATA "MetaQuotes\Terminal"
    if (-not (Test-Path $root)) { return $out }
    Get-ChildItem -Path $root -Directory | ForEach-Object {
        $mql4 = Join-Path $_.FullName "MQL4"
        if (Test-Path (Join-Path $mql4 "Indicators\BiotakProject")) { $out += $mql4 }
    }
    return $out
}

#--- P-BUILD-10 (2026-10-01) — THE TERMINAL'S OWN HANDS, IN THREE PIECES.
#--- The deploy restart and the strip shot both need the same three moves (capture
#--- what is running, stop it, put it back), so they share them: one owner per move,
#--- read by `Restart-TradingTerminal` and by `Invoke-StripShot` below.
function Get-TerminalStarts {
    $procs = Get-WmiObject Win32_Process -Filter "Name='terminal.exe'" -ErrorAction SilentlyContinue
    $starts = @()
    foreach ($p in $procs) {
        $exe = $p.ExecutablePath
        if (-not $exe) { continue }
        $args = ""
        $cmd = [string]$p.CommandLine
        if ($cmd) {
            $q = '"' + $exe + '"'
            if ($cmd.StartsWith($q)) { $args = $cmd.Substring($q.Length).Trim() }
            elseif ($cmd.StartsWith($exe)) { $args = $cmd.Substring($exe.Length).Trim() }
        }
        $starts += @{ Exe = $exe; Args = $args }
    }
    if ($procs -and $starts.Count -eq 0) {
        Write-Host "  Terminal processes found but their paths are unreadable; not restarting." -ForegroundColor Red
    }
    return ,$starts
}

function Stop-TerminalProcesses {
    # Graceful first: CloseMainWindow lets MT4 save its profile and charts.
    foreach ($pr in @(Get-Process -Name "terminal" -ErrorAction SilentlyContinue)) {
        try { $null = $pr.CloseMainWindow() } catch {}
    }
    $deadline = (Get-Date).AddSeconds(25)
    do {
        Start-Sleep -Milliseconds 500
        $alive = @(Get-Process -Name "terminal" -ErrorAction SilentlyContinue)
    } while ($alive.Count -gt 0 -and (Get-Date) -lt $deadline)
    $alive = @(Get-Process -Name "terminal" -ErrorAction SilentlyContinue)
    if ($alive.Count -gt 0) {
        Write-Host "  Terminal did not close gracefully; forcing..." -ForegroundColor Yellow
        $alive | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    $alive = @(Get-Process -Name "terminal" -ErrorAction SilentlyContinue)
    if ($alive.Count -gt 0) {
        Write-Host "  [FAIL] terminal.exe is still alive; not relaunching into an unknown state." -ForegroundColor Red
        return $false
    }
    return $true
}

function Start-TerminalStarts {
    param($Starts)
    foreach ($s in $Starts) {
        if ($s.Args) { Start-Process -FilePath $s.Exe -ArgumentList $s.Args }
        else { Start-Process -FilePath $s.Exe }
    }
}

function Restart-TradingTerminal {
    #--- P-BUILD-07: THE DEPLOY LOOP, CLOSED. MT4 runs what it loaded at attach;
    #--- a fresh ex4 is a file until the terminal restarts or the indicator is
    #--- removed and re-added. Re-add is manual and per-chart; a restart reloads
    #--- EVERY chart from the new ex4 in one step. Opt-in only (-RestartTerminal):
    #--- killing the terminal also stops anything else it hosts, so this never
    #--- runs unless asked. Each instance is relaunched with its OWN executable
    #--- path and command line (portable/datapath flags survive), so the same
    #--- data folder — and the same charts — come back.
    $procs = @(Get-WmiObject Win32_Process -Filter "Name='terminal.exe'" -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) {
        Write-Host "  No running terminal.exe found; nothing to restart." -ForegroundColor Yellow
        return $true
    }
    $starts = Get-TerminalStarts
    if ($starts.Count -eq 0) { return $false }
    Write-Host "  Restarting $($starts.Count) terminal process(es) so the new ex4 loads..." -ForegroundColor Yellow
    foreach ($s in $starts) { Write-Host "    will relaunch: $($s.Exe) $($s.Args)" -ForegroundColor DarkGray }
    if (-not (Stop-TerminalProcesses)) { return $false }
    Start-TerminalStarts -Starts $starts
    Write-Host "  Terminal restarted. Charts come back on their own; every indicator reloads from the new ex4." -ForegroundColor Green
    return $true
}

# ══════════════════════════════════════════════════════════════════════════
# P-BUILD-10 (2026-10-01) — THE REAL RENDER, ONE COMMAND.
#
# `tests/Biotak_StripShot_Test.mq4` paints every state of the strip and ALL FOUR
# `Box Settings` tabs through the REAL paint path, writes `StripShot_<tag>.png`
# into `<MQL4>\Files` and prints one `[STRIPSHOT] obj …` line per object with the
# rect the TERMINAL built. `tools/before-after.py` already puts those beside the
# design and the sim (tools/mt4-shots -> tools/before-after.html). The only missing
# piece was the RUN: the harness had to be dragged onto a chart by hand.
#
# MT4 answers it in its own words — "Configuration at Startup" (documented at
# metatrader4.com, Tools): `Script=` in a config file names the script the terminal
# launches on startup, on the chart its own `Symbol`/`Period` open. That extra chart
# is NOT saved to the profile, so the live charts come back untouched.
#
#   -Shot                     compile the harness, deploy it into the instance's
#                             Scripts\, write the config, print the one command to
#                             run. Nothing is closed.
#   -Shot -RestartTerminal    close MT4, launch it on the shot config, wait for
#                             `[STRIPSHOT] DONE:`, collect the census + PNGs into
#                             build-logs\shot\, bring the closed instances back, and
#                             rebuild the before/after page.
# ══════════════════════════════════════════════════════════════════════════
function Set-TerminalShotConfig {
    param([string]$Path, [string]$Symbol, [string]$Period, [string]$Script)
    #--- MT4's own `Configuration at Startup` (Tools > Configuration at Startup in
    #--- the 4 help): flat `Parameter=Value` lines, `;` starts a comment, no sections.
    #--- `Symbol`/`Period` open ONE EXTRA chart which is NOT saved to the profile, and
    #--- `Script` is the script's NAME (its path is <data>\MQL4\Scripts\). `ExpertsEnable`
    #--- is stated here because the Extra chart's script obeys the Experts switch: a
    #--- user with AutoTrading off would otherwise get a silent no-op and a 120s wait.
    $ini = @("; P-BUILD-10 - MT4 Configuration at Startup.",
             "; One extra chart, opened by MT4 for this launch only and never saved to",
             "; the profile, so the user's charts and indicators come back as they were.",
             "Symbol=$Symbol",
             "Period=$Period",
             "Script=$Script",
             "ExpertsEnable=true")
    Set-Content -LiteralPath $Path -Value $ini -Encoding ASCII
}

function Get-LatestTerminalLog {
    param([string]$Mql4Dir)
    $dir = Join-Path $Mql4Dir "Logs"
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    return (Get-ChildItem -LiteralPath $dir -Filter *.log -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1)
}

function Wait-TerminalShotLines {
    # The harness's own voice, read where MT4 writes it: <MQL4>\Logs\<date>.log,
    # UTF-16. Only lines AFTER the launch are taken (a previous run's lines are not
    # this run's answer), and the wait ends on DONE / SKIP / a failed shot.
    param([string]$Mql4Dir, [int]$TimeoutSec, [string]$LogPath, [int]$SkipLines)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $out = @()
    $cur = $LogPath
    $skip = $SkipLines
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 700
        $latest = Get-LatestTerminalLog -Mql4Dir $Mql4Dir
        if (-not $latest) { continue }
        if ($latest.FullName -ne $cur) { $cur = $latest.FullName; $skip = 0 }
        $all = @(Get-Content -LiteralPath $cur -Encoding Unicode -ErrorAction SilentlyContinue)
        if ($all.Count -le $skip) { continue }
        $fresh = @($all[$skip..($all.Count - 1)] | Where-Object { $_.Contains("[STRIPSHOT]") })
        if ($fresh.Count -gt 0) {
            $out += $fresh
            $stop = @($fresh | Where-Object {
                $_.Contains("DONE:") -or $_.Contains("SKIP") -or $_.Contains("FAILED") })
            if ($stop.Count -gt 0) { break }
        }
        $skip = $all.Count
    }
    return ,$out
}

function Invoke-StripShot {
    param([string]$Mql4Dir, [string]$Symbol, [string]$Period, [int]$TimeoutSec, [switch]$Launch)
    $harness = "Biotak_StripShot_Test"
    $ex4 = Join-Path $SCRIPT_ROOT "tests\$harness.ex4"
    if (-not (Test-Path -LiteralPath $ex4)) {
        Write-Host "  [FAIL] $harness.ex4 was not built — the shot needs -Tests (or -Shot alone compiles it)." -ForegroundColor Red
        return $false
    }
    $scripts = Join-Path $Mql4Dir "Scripts"
    if (-not (Test-Path -LiteralPath $scripts)) { New-Item -ItemType Directory -Path $scripts -Force | Out-Null }
    Copy-Item -LiteralPath $ex4 -Destination (Join-Path $scripts "$harness.ex4") -Force
    Write-Host "  harness: $scripts\$harness.ex4" -ForegroundColor DarkGray
    $configPath = Join-Path $PROJECT_LOG_DIR "th3-shot.ini"
    Set-TerminalShotConfig -Path $configPath -Symbol $Symbol -Period $Period -Script $harness
    Write-Host "  config:  $configPath  (Symbol=$Symbol Period=$Period Script=$harness)" -ForegroundColor DarkGray

    if (-not $Launch) {
        Write-Host ""
        Write-Host "  NEXT: close MT4, then run:" -ForegroundColor Yellow
        Write-Host "        terminal.exe /config:`"$configPath`"" -ForegroundColor Yellow
        Write-Host "        (or re-run this build with -Shot -RestartTerminal and it does it all)" -ForegroundColor DarkGray
        return $true
    }

    $procs = @(Get-WmiObject Win32_Process -Filter "Name='terminal.exe'" -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) {
        Write-Host "  [FAIL] no terminal.exe is running, so there is no instance to launch." -ForegroundColor Red
        Write-Host "         Start MT4 once, then re-run -Shot -RestartTerminal." -ForegroundColor Yellow
        return $false
    }
    $starts = Get-TerminalStarts
    if ($starts.Count -eq 0) { return $false }
    # the instance that carries its own data folder (portable/datapath) is the one
    # this repo deploys into; otherwise the first one.
    $shotStart = $starts[0]
    foreach ($s in $starts) { if ($s.Args -match "portable|datapath") { $shotStart = $s; break } }
    Write-Host "  shot instance: $($shotStart.Exe) $($shotStart.Args)" -ForegroundColor DarkGray
    Write-Host "  script must be in THAT instance's Scripts\ — deployed to $scripts" -ForegroundColor DarkGray
    if (-not (Stop-TerminalProcesses)) { return $false }

    $logBefore = Get-LatestTerminalLog -Mql4Dir $Mql4Dir
    $skip = 0
    $logPath = ""
    if ($logBefore) {
        $logPath = $logBefore.FullName
        $skip = @(Get-Content -LiteralPath $logPath -Encoding Unicode -ErrorAction SilentlyContinue).Count
    }
    $shotArgs = ("$($shotStart.Args) /config:`"$configPath`"").Trim()
    Start-Process -FilePath $shotStart.Exe -ArgumentList $shotArgs
    Write-Host "  launched; waiting up to ${TimeoutSec}s for [STRIPSHOT] DONE:..." -ForegroundColor Cyan
    $lines = @(Wait-TerminalShotLines -Mql4Dir $Mql4Dir -TimeoutSec $TimeoutSec -LogPath $logPath -SkipLines $skip)

    # the shot instance has done its job: put the user's own terminal back
    if (-not (Stop-TerminalProcesses)) { return $false }
    Start-TerminalStarts -Starts $starts
    Write-Host "  terminal relaunched ($($starts.Count) instance(s))" -ForegroundColor Green

    $shotDir = Join-Path $PROJECT_LOG_DIR "shot"
    if (-not (Test-Path -LiteralPath $shotDir)) { New-Item -ItemType Directory -Path $shotDir -Force | Out-Null }
    $census = Join-Path $shotDir "StripShot-census.txt"
    if ($lines.Count -eq 0) {
        Write-Host "  [FAIL] no [STRIPSHOT] line appeared in $Mql4Dir\Logs within ${TimeoutSec}s" -ForegroundColor Red
        Write-Host "         (the script did not run on that instance — check its Experts tab)" -ForegroundColor Yellow
        return $false
    }
    $lines | Set-Content -LiteralPath $census -Encoding UTF8
    $bad = @($lines | Where-Object { $_.Contains("FAILED") -or $_.Contains("SKIP") })
    $done = @($lines | Where-Object { $_.Contains("DONE:") })
    foreach ($l in $bad) { Write-Host "    $l" -ForegroundColor Yellow }
    foreach ($tag in @("panel_paint", "panel_style", "panel_look", "panel_row")) {
        $sum = @($lines | Where-Object { $_.Contains(" $tag objs=") })
        if ($sum.Count -gt 0) { Write-Host "    $($sum[0])" -ForegroundColor DarkGray }
    }
    $png = @(Get-ChildItem -LiteralPath (Join-Path $Mql4Dir "Files") -Filter "StripShot_*.png" -File -ErrorAction SilentlyContinue | Sort-Object Name)
    foreach ($p in $png) { Copy-Item -LiteralPath $p.FullName -Destination (Join-Path $shotDir $p.Name) -Force }
    Write-Host "  census: $census  (lines=$($lines.Count))" -ForegroundColor DarkGray
    Write-Host "  terminal PNGs: $($png.Count) -> $shotDir" -ForegroundColor Green
    if ($done.Count -eq 0) {
        Write-Host "  [FAIL] the harness never reached DONE (see $census)" -ForegroundColor Red
        return $false
    }
    #--- A DONE with no file behind it is the P-DRAW-06 class again (an object created,
    #--- a property written, nothing painted): green line, empty column. The shot's whole
    #--- job is the pixels, so the pixels are what it is graded on.
    if ($png.Count -eq 0) {
        Write-Host "  [FAIL] the harness reached DONE but wrote no StripShot_*.png into $Mql4Dir\Files" -ForegroundColor Red
        Write-Host "         (ChartScreenShot needs a visible / unminimised chart window)" -ForegroundColor Yellow
        return $false
    }
    return $true
}

function Get-UnitFiles {
    # Every file one entry pulls in, transitively. A #resource is per COMPILING
    # UNIT, so "is this raster declared" is a question about the unit, never about
    # one file.
    param([string]$EntryAbs)
    $seen = New-Object System.Collections.Generic.HashSet[string]
    $out = New-Object System.Collections.Generic.List[string]
    $queue = New-Object System.Collections.Generic.Queue[string]
    $queue.Enqueue($EntryAbs)
    while ($queue.Count -gt 0) {
        $f = $queue.Dequeue()
        if (-not $f -or $seen.Contains($f) -or -not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
        $seen.Add($f) | Out-Null
        $out.Add($f)
        $dir = Split-Path -Parent $f
        foreach ($line in (Get-Content -LiteralPath $f -ErrorAction SilentlyContinue)) {
            if ($line -match '^\s*#include\s+"([^"]+)"') {
                $rel = $Matches[1] -replace '\\', [IO.Path]::DirectorySeparatorChar
                $abs = Join-Path $dir $rel
                if (-not (Test-Path -LiteralPath $abs)) { $abs = Join-Path $SCRIPT_ROOT $rel }
                if (Test-Path -LiteralPath $abs) { $queue.Enqueue($abs) }
            }
        }
    }
    return $out
}

function Assert-ResourceTree {
    # P-BUILD-03 (measured 2026-09-25, 325 errors): MetaEditor resolves
    # `#resource "\Files\Icons\x.bmp"` against the SOURCE FILE'S OWN TREE. The only
    # tree that matters is the one beside the file being compiled.
    #
    # This REPLACED an `Sync-IconsToTerminal` that copied ~10 MB of icons into
    # every hosting terminal's MQL4\Files\Icons. That copy was measured INERT (the
    # junction makes Indicators\BiotakProject resolve back to this repo, so the
    # resources were read from here all along) and its own comment contradicted
    # P-BUILD-03. It was write amplification that could not have fixed a missing
    # icon and could only hide one.
    $missing = @()
    $entries = @("Biotak Trigger TH3.mq4", "Biotak Trigger TH3 Lite.mq4")
    foreach ($t in (Get-ChildItem (Join-Path $SCRIPT_ROOT "tests") -Filter *.mq4 -ErrorAction SilentlyContinue)) {
        $entries += $t.Name
    }
    foreach ($e in $entries) {
        $entryAbs = Join-Path $SCRIPT_ROOT $e
        if (-not (Test-Path $entryAbs)) { continue }
        $dir = Split-Path -Parent $entryAbs
        $declared = New-Object System.Collections.Generic.HashSet[string]
        foreach ($f in (Get-UnitFiles -EntryAbs $entryAbs)) {
            foreach ($line in (Get-Content -LiteralPath $f -ErrorAction SilentlyContinue)) {
                if ($line -match '^\s*#resource\s+"\\+Files\\+Icons\\+([^"]+)"') { $declared.Add($Matches[1]) | Out-Null }
            }
        }
        foreach ($n in $declared) {
            $tree = Join-Path (Join-Path (Join-Path $dir "Files") "Icons") $n
            if (-not (Test-Path -LiteralPath $tree -PathType Leaf)) { $missing += "$e -> $n" }
        }
    }
    if ($missing.Count -gt 0) {
        Write-Host "  ERROR: $($missing.Count) declared raster(s) not in the compiler's tree:" -ForegroundColor Red
        foreach ($m in ($missing | Select-Object -First 12)) { Write-Host "    $m" -ForegroundColor Red }
        return $false
    }
    return $true
}

function Sync-IconsToTerminal {
    param([string]$ResolvedMql4Dir)

    # MetaEditor resolves "#resource \Files\Icons\..." against the TERMINAL's
    # MQL4\Files folder, not this workspace. A project may be reachable from
    # several MT4 terminals (e.g. Indicators\BiotakProject is a symlink back
    # to this repo), so sync into EVERY terminal that hosts this project -
    # otherwise a stale copy silently embeds old icons on the next compile.
    $src = Join-Path $SCRIPT_ROOT "Files\Icons"
    if (-not (Test-Path $src)) { return }

    $dirs = New-Object System.Collections.Generic.List[string]
    foreach ($d in @($ResolvedMql4Dir) + (Get-TerminalMql4DirsForProject)) {
        if ($d -and (Test-Path $d) -and -not $dirs.Contains($d)) { $dirs.Add($d) }
    }

    foreach ($mql4 in $dirs) {
        $dst = Join-Path $mql4 "Files\Icons"
        if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }
        $copied = 0
        Get-ChildItem -Path $src -Filter "*.bmp" | ForEach-Object {
            $target = Join-Path $dst $_.Name
            if (-not (Test-Path $target) -or (Get-FileHash $_.FullName).Hash -ne (Get-FileHash $target).Hash) {
                Copy-Item -LiteralPath $_.FullName -Destination $target -Force
                $copied++
            }
        }
        if ($copied -gt 0) { Write-Host "  Icon sync: copied $copied updated BMP(s) to $dst" -ForegroundColor DarkCyan }
    }
}

function Update-BuildHash {
    #--- P-BUILD-08: ONE SOURCE IDENTITY FOR EVERY STAMP THE PANEL AND LOG PRINT.
    #--- The stamps used to be hand-typed: `TH3_BUILD_TAG "T2"` and
    #--- `INDICATOR_BUILD_TAG "D4m-native 2026-09-20"`. Neither changes when the
    #--- code changes, so every build of 2026-09-29 printed the SAME [BUILD] line
    #--- and a chart running an hours-old ex4 was indistinguishable from a fresh
    #--- one. tools/gen-build-hash.js writes a SHA-256 over the bytes this unit
    #--- compiles (entries + transitive includes + embedded rasters) into
    #--- Biotak\BuildHash.mqh, which the MQL prints. The build cannot emit a stamp
    #--- it cannot justify, so a failure here stops the build instead of shipping
    #--- a banner with a stale word in it.
    $gen = Join-Path $SCRIPT_ROOT "tools\gen-build-hash.js"
    if (-not (Test-Path $gen)) {
        Write-Host "  ERROR: tools\gen-build-hash.js not found - no truthful build stamp is possible." -ForegroundColor Red
        return $null
    }
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Host "  ERROR: node is required to generate Biotak\BuildHash.mqh." -ForegroundColor Red
        return $null
    }
    $line = [string]((& node $gen) | Select-Object -Last 1)
    if ($LASTEXITCODE -ne 0 -or -not $line) {
        Write-Host "  ERROR: build-hash generation failed." -ForegroundColor Red
        return $null
    }
    $m = [regex]::Match($line, 'hash=([0-9a-f]+)\s+short=([0-9a-f]+)\s+files=(\d+)')
    if (-not $m.Success) {
        Write-Host "  ERROR: unexpected build-hash output: $line" -ForegroundColor Red
        return $null
    }
    $stamp = @{ Hash = $m.Groups[1].Value; Short = $m.Groups[2].Value; Files = $m.Groups[3].Value }
    Write-Host ("  Build src: {0} ({1} files) -> Biotak\BuildHash.mqh" -f $stamp.Hash, $stamp.Files) -ForegroundColor Cyan
    return $stamp
}

function Write-SourceStamp {
    #--- P-BUILD-08: the ONE file that can CONTRADICT a running ex4.
    #--- MT4 keeps the loaded indicator in memory, so after a build a chart can
    #--- still run an older ex4 that prints the SAME banner. This drops the hash
    #--- the build just produced beside every terminal that hosts this project
    #--- (MQL4\Files\th3-src.txt, the indicator's own sandbox root); at attach the
    #--- indicator compares it with the hash compiled INTO it and prints
    #--- `srcfile=<hash> match=yes|NO`. No clock is written to this file - only the
    #--- hash - so a build that changed nothing does not rewrite it, and there is
    #--- no second date in the repo that can drift.
    param([hashtable]$Stamp, [string]$ResolvedMql4Dir)
    if (-not $Stamp) { return }
    $dirs = New-Object System.Collections.Generic.List[string]
    foreach ($d in @($ResolvedMql4Dir) + (Get-TerminalMql4DirsForProject)) {
        if ($d -and (Test-Path $d) -and -not $dirs.Contains($d)) { $dirs.Add($d) }
    }
    if ($dirs.Count -eq 0) {
        Write-Host "  Source stamp: no terminal MQL4 dir found; the ex4 will report srcfile=none." -ForegroundColor Yellow
        return
    }
    #--- P-BUILD-08b: THE SHADOW COPY THAT ANSWERS FOR THE WRONG BUILD.
    #--- MT4 attaches an indicator by NAME, and it searches Indicators\ root
    #--- before Indicators\BiotakProject. A leftover `Biotak Trigger TH3.ex4` in the
    #--- root therefore wins, and every chart silently runs THAT file - measured
    #--- 2026-09-29: a 2,534,402-byte ex4 dated 2026-09-20 sat in
    #--- Terminal\0727F3F8...\MQL4\Indicators\ while the live logs carried
    #--- `Custom indicator Biotak Trigger TH3` (root) and `...BiotakProject\Biotak
    #--- Trigger TH3` (this repo) on different charts of the same terminal. Not a
    #--- build failure and not a compile error: two files, one name. It is reported
    #--- here and never deleted by this script.
    foreach ($mql4 in $dirs) {
        foreach ($nm in @("Biotak Trigger TH3", "Biotak Trigger TH3 Lite")) {
            foreach ($ext in @(".ex4", ".mq4")) {
                $shadow = Join-Path $mql4 "Indicators\$nm$ext"
                if (Test-Path -LiteralPath $shadow) {
                    $sh = Get-Item -LiteralPath $shadow
                    $age = $sh.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                    #--- P-BUILD-08c (2026-09-29) — THE SHADOW IS NOW REPLACED, NOT
                    #--- ONLY REPORTED. Reporting was the wrong verb: the user was
                    #--- told about this file in the build output for a day and the
                    #--- chart kept loading it, because "a warning the operator has
                    #--- to act on" is not a fix. MT4 resolves an indicator by NAME
                    #--- and searches Indicators\ root BEFORE Indicators\BiotakProject,
                    #--- so with both files present the root one can win under the
                    #--- SAME name - measured 2026-09-29: root 2,534,402 bytes dated
                    #--- 2026-09-20 11:17 beside a fresh 3,45x,xxx-byte build, and
                    #--- the chart then paints the old code while the log prints the
                    #--- new banner. The fresh file already sits next to it through
                    #--- the project junction, so the two are compared byte for byte
                    #--- and the shadow is overwritten only when they differ. The
                    #--- SOURCE (.mq4) in the root folder is still never written:
                    #--- only a compiled ex4 of this project's own name.
                    $fresh = Join-Path $mql4 "Indicators\BiotakProject\$nm$ext"
                    if ($ext -eq ".ex4" -and (Test-Path -LiteralPath $fresh)) {
                        $fr = Get-Item -LiteralPath $fresh
                        #--- size first (free), then the bytes: two builds of an
                        #--- unchanged tree differ in size, so the hash is only paid
                        #--- when the two files look alike.
                        $same = $false
                        if ($sh.Length -eq $fr.Length) {
                            $same = ((Get-FileHash -Algorithm MD5 -LiteralPath $shadow).Hash -eq
                                     (Get-FileHash -Algorithm MD5 -LiteralPath $fresh).Hash)
                        }
                        if (-not $same) {
                            Copy-Item -LiteralPath $fresh -Destination $shadow -Force
                            Write-Host ("  Shadow replaced: {0} ({1:N0} bytes, {2}) -> {3:N0} bytes, {4}" -f `
                                $shadow, $sh.Length, $age, $fr.Length, $fr.LastWriteTime.ToString("HH:mm:ss")) -ForegroundColor Green
                        }
                        else {
                            Write-Host "  Shadow already current: $shadow" -ForegroundColor DarkGray
                        }
                    }
                    else {
                        Write-Host "  WARNING: shadow copy $shadow ($age) has no fresh counterpart to replace it with." -ForegroundColor Red
                    }
                }
            }
        }
    }

    $body = "hash={0} short={1} files={2}" -f $Stamp.Hash, $Stamp.Short, $Stamp.Files
    foreach ($mql4 in $dirs) {
        $files = Join-Path $mql4 "Files"
        if (-not (Test-Path $files)) { New-Item -ItemType Directory -Path $files -Force | Out-Null }
        $target = Join-Path $files "th3-src.txt"
        $have = if (Test-Path -LiteralPath $target) { [string](Get-Content -LiteralPath $target -Raw -ErrorAction SilentlyContinue) } else { "" }
        if ($have.Trim() -ne $body) {
            Set-Content -LiteralPath $target -Value $body -Encoding ASCII
            Write-Host "  Source stamp: $target -> $($Stamp.Hash)" -ForegroundColor DarkCyan
        }
        else {
            Write-Host "  Source stamp: $target unchanged ($($Stamp.Hash))" -ForegroundColor DarkGray
        }
    }
}

function Compile-MQL4 {
    param(
        [string]$Name,
        [string]$SourcePath,
        [string]$CompilerPath,
        [string]$ResolvedMql4Dir,
        [string]$TerminalRoot
    )
    
    Write-Banner "Compiling: $Name"
    
    # Validate paths
    if (-not (Test-Path -LiteralPath $CompilerPath -PathType Leaf)) {
        Write-Host "  ERROR: MetaEditor not found at: $CompilerPath" -ForegroundColor Red
        Write-Host "  Hint: Use -MetaEditorPath or MT4_METAEDITOR env variable." -ForegroundColor Yellow
        return $false
    }
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        Write-Host "  ERROR: Source file not found: $SourcePath" -ForegroundColor Red
        return $false
    }
    if ([System.IO.Path]::GetExtension($SourcePath) -ine ".mq4") {
        Write-Host "  ERROR: Source file must be a .mq4 file: $SourcePath" -ForegroundColor Red
        return $false
    }
    
    if (-not (Test-Path $PROJECT_LOG_DIR)) {
        New-Item -ItemType Directory -Path $PROJECT_LOG_DIR -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $safeName = ($Name -replace '[^A-Za-z0-9_-]', '-')
    $logFile = Join-Path $PROJECT_LOG_DIR ("{0}-{1}.log" -f $safeName, $timestamp)

    $includePath = Get-IncludePath -SourcePath $SourcePath -ScriptRoot $SCRIPT_ROOT -ResolvedMql4Dir $ResolvedMql4Dir

    #--- P-DRAFT-01: the icon TREE is asserted, not copied. `Sync-IconsToTerminal`
    #--- ran here and pushed ~10 MB of BMPs into every hosting terminal for a
    #--- resolution MetaEditor does not use (P-BUILD-03: the SOURCE's own tree).
    if (-not (Assert-ResourceTree)) { return $false }

    #--- the artifact, BEFORE and AFTER. "It compiled" is not a claim anyone can
    #--- check: a stale ex4 and a fresh one both print Result: 0 errors. The
    #--- size+mtime pair is what makes the deploy question answerable.
    $ex4Path = [System.IO.Path]::ChangeExtension($SourcePath, ".ex4")
    $ex4Before = if (Test-Path -LiteralPath $ex4Path -PathType Leaf) { (Get-Item $ex4Path) } else { $null }
    if ($ex4Before) {
        Write-Host ("  ex4 before: {0:N0} bytes  {1}" -f $ex4Before.Length, $ex4Before.LastWriteTime.ToString("HH:mm:ss")) -ForegroundColor DarkGray
    } else {
        Write-Host "  ex4 before: (none)" -ForegroundColor DarkGray
    }
    
    Write-Host "  Source:   $SourcePath" -ForegroundColor Gray
    Write-Host "  Include:  $includePath" -ForegroundColor Gray
    Write-Host "  Log:      $logFile" -ForegroundColor Gray
    Write-Host ""
    
    # Run compiler
    # MT4 MetaEditor uses the same /compile /log /include flags
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $proc = Start-Process -FilePath $CompilerPath `
        -ArgumentList "/compile:`"$SourcePath`"", "/log:`"$logFile`"", "/include:`"$includePath`"" `
        -PassThru -Wait -NoNewWindow
    $stopwatch.Stop()
    $exitCode = $proc.ExitCode
    
    # Wait for log file to be written
    $logReady = Wait-ForFile -Path $logFile
    
    # Parse results
    if (-not $logReady) {
        Write-Host "  WARNING: Log file was not created" -ForegroundColor Yellow
        Write-Host "  Compiler exit code: $exitCode" -ForegroundColor Yellow
        return $false
    }
    
    $logContent = Read-LogContent -Path $logFile
    
    $errors   = @()
    $warnings = @()
    $resultLine = ""
    
    foreach ($line in $logContent) {
        if ($line -match ": error \d+:") {
            $errors += $line
        }
        elseif ($line -match ": warning \d+:") {
            $warnings += $line
        }
        elseif ($line -match "^Result:") {
            $resultLine = $line
        }
    }
    
    # Display errors
    if ($errors.Count -gt 0) {
        Write-Host "  ERRORS ($($errors.Count)):" -ForegroundColor Red
        foreach ($err in $errors) {
            # Shorten the path for readability
            $short = $err -replace [regex]::Escape($SCRIPT_ROOT + "\"), ""
            if ($ResolvedMql4Dir) {
                $short = $short -replace [regex]::Escape($ResolvedMql4Dir + "\Indicators\"), ""
            }
            Write-Host "    $short" -ForegroundColor Red
        }
        Write-Host ""
    }
    
    # Display warnings
    if ($warnings.Count -gt 0) {
        Write-Host "  WARNINGS ($($warnings.Count)):" -ForegroundColor Yellow
        foreach ($w in $warnings) {
            $short = $w -replace [regex]::Escape($SCRIPT_ROOT + "\"), ""
            if ($ResolvedMql4Dir) {
                $short = $short -replace [regex]::Escape($ResolvedMql4Dir + "\Indicators\"), ""
            }
            Write-Host "    $short" -ForegroundColor Yellow
        }
        Write-Host ""
    }
    
    # Result summary
    if ($resultLine) {
        if ($errors.Count -eq 0) {
            Write-Host "  $resultLine" -ForegroundColor Green
        } else {
            Write-Host "  $resultLine" -ForegroundColor Red
        }
    }

    if ($exitCode -ne 0 -and $errors.Count -gt 0) {
        Write-Host "  Compiler exit code: $exitCode" -ForegroundColor Red
    }
    elseif ($exitCode -ne 0) {
        Write-Host "  Compiler exit code: $exitCode (non-fatal, no compile errors in log)" -ForegroundColor Yellow
    }

    if ($PrintLog -and $logContent) {
        Write-Host ""
        if ($LogTailLines -gt 0) {
            Write-Host "  LOG OUTPUT (last $LogTailLines lines):" -ForegroundColor Cyan
            $linesToPrint = $logContent | Select-Object -Last $LogTailLines
        }
        else {
            Write-Host "  LOG OUTPUT (full):" -ForegroundColor Cyan
            $linesToPrint = $logContent
        }

        foreach ($l in $linesToPrint) {
            if ($l -match ": error \d+:") {
                Write-Host "    $l" -ForegroundColor Red
            }
            elseif ($l -match ": warning \d+:") {
                Write-Host "    $l" -ForegroundColor Yellow
            }
            else {
                Write-Host "    $l" -ForegroundColor DarkGray
            }
        }
        Write-Host ""
    }

    if ($IncludeRuntimeLogs) {
        $runtimeState = Load-RuntimeState -StatePath $RUNTIME_STATE_FILE
        Append-RuntimeLogs -CompileLogPath $logFile -ResolvedMql4Dir $ResolvedMql4Dir -TerminalRoot $TerminalRoot -TailLines $RuntimeLogTailLines -PrintToConsole $PrintLog -UseIncremental $IncrementalRuntimeLogs -State $runtimeState
        Save-RuntimeState -StatePath $RUNTIME_STATE_FILE -State $runtimeState
        Write-Host "  Runtime snapshot appended to: $logFile" -ForegroundColor Gray
        Write-Host ""
    }
    
    $elapsed = $stopwatch.Elapsed.TotalSeconds.ToString("F1")
    Write-Host "  Compile time: ${elapsed}s" -ForegroundColor Gray
    
    #--- P-DRAFT-01: the artifact, AFTER. A build that prints 0 errors but leaves
    #--- the ex4 untouched has changed nothing the terminal will ever load, and
    #--- that is the single hardest failure to see from the outside.
    $ex4After = if (Test-Path -LiteralPath $ex4Path -PathType Leaf) { Get-Item $ex4Path } else { $null }
    if (-not $ex4After) {
        Write-Host "  Output: (none produced)" -ForegroundColor Red
    }
    else {
        $delta = if ($ex4Before) { [long]$ex4After.Length - [long]$ex4Before.Length } else { $ex4After.Length }
        $sign = if ($delta -ge 0) { "+" } else { "" }
        Write-Host ("  Output: {0} ({1:N0} bytes, {2} {3}{4:N0})" -f `
            $ex4Path, $ex4After.Length, $ex4After.LastWriteTime.ToString("HH:mm:ss"), $sign, $delta) -ForegroundColor Green
        if ($ex4Before -and $ex4After.LastWriteTime -le $ex4Before.LastWriteTime) {
            Write-Host "  WARNING: ex4 was NOT rewritten - the terminal is still running the previous build" -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
    
    if ($errors.Count -gt 0) {
        return $false
    }

    # MetaEditor can return non-zero in some environments even when compilation succeeded.
    # We trust log parsing as the primary success indicator.
    return $true
}

function Get-InstalledProjectSource {
    param([string]$ResolvedMql4Dir)
    # The installed project lives wherever Indicators\BiotakProject exists
    # (usually a symlink to this repo inside one of the MT4 terminals).
    $candidates = @($ResolvedMql4Dir) + (Get-TerminalMql4DirsForProject)
    foreach ($mql4 in $candidates) {
        $mq4 = Join-Path $mql4 "Indicators\BiotakProject\Biotak Trigger TH3.mq4"
        if ($mql4 -and (Test-Path $mq4)) { return $mq4 }
    }
    return ""
}

# ============================================================
# MAIN EXECUTION
# ============================================================

$startTime = Get-Date
$results = @{}

#--- P-BUILD-09: the gate MODE, its cache and its one fingerprint — resolved here,
#--- before any gate, so a scoped run can say [SKIP] instead of running and hoping.
$gateMode = if ($Fast) { "off" } else { $Gates }
$gateCachePath = Join-Path $SCRIPT_ROOT "build-logs\gate-cache.json"
$gateCacheDirty = $false
$gateFingerprint = ""

function Get-TreeFingerprint {
    # EVERY input every gate reads, in ONE hash: the modules, the two entries, the
    # tools (a gate is part of its own input) and the rasters. Deliberately coarser
    # than per-gate, because one shared fingerprint cannot miss a file a gate reads
    # and a per-gate list forgets — the single way a cache like this goes wrong.
    $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    $biotak = Join-Path $SCRIPT_ROOT "Biotak"
    if (Test-Path -LiteralPath $biotak) {
        foreach ($f in Get-ChildItem -LiteralPath $biotak -Recurse -File) {
            if ($f.Extension -eq ".mqh" -or $f.Extension -eq ".mq4") { $files.Add($f) }
        }
    }
    foreach ($e in @("Biotak Trigger TH3.mq4", "Biotak Trigger TH3 Lite.mq4")) {
        $p = Join-Path $SCRIPT_ROOT $e
        if (Test-Path -LiteralPath $p) { $files.Add((Get-Item -LiteralPath $p)) }
    }
    $tools = Join-Path $SCRIPT_ROOT "tools"
    if (Test-Path -LiteralPath $tools) {
        foreach ($f in Get-ChildItem -LiteralPath $tools -Recurse -File) {
            if ($f.Extension -eq ".js" -or $f.Extension -eq ".py") { $files.Add($f) }
        }
    }
    $icons = Join-Path $SCRIPT_ROOT "Files\Icons"
    if (Test-Path -LiteralPath $icons) {
        foreach ($f in Get-ChildItem -LiteralPath $icons -File) { $files.Add($f) }
    }
    $ordered = @($files | Sort-Object FullName)
    $sha = [System.Security.Cryptography.SHA1]::Create()
    $ms = New-Object System.IO.MemoryStream
    foreach ($f in $ordered) {
        $nb = [System.Text.Encoding]::UTF8.GetBytes($f.FullName)
        $bb = [System.IO.File]::ReadAllBytes($f.FullName)
        $ms.Write($nb, 0, $nb.Length)
        $ms.Write($bb, 0, $bb.Length)
    }
    $fp = ([System.BitConverter]::ToString($sha.ComputeHash($ms.ToArray()))).Replace("-", "").Substring(0, 16)
    $ms.Dispose()
    $sha.Dispose()
    Write-Host "  gate fingerprint: $fp over $($ordered.Count) file(s)" -ForegroundColor DarkGray
    return $fp
}

function Read-GateCache {
    $cache = @{}
    if (-not (Test-Path -LiteralPath $gateCachePath)) { return $cache }
    try {
        $raw = Get-Content -LiteralPath $gateCachePath -Raw -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            foreach ($p in ($raw | ConvertFrom-Json).PSObject.Properties) {
                $cache[$p.Name] = [string]$p.Value
            }
        }
    }
    catch { $cache = @{} }
    return $cache
}

function Save-GateCache {
    param($Cache)
    try {
        ($Cache | ConvertTo-Json -Compress) | Set-Content -LiteralPath $gateCachePath -Encoding UTF8 -ErrorAction Stop
    }
    catch { Write-Host "  WARN: gate cache not written ($($_.Exception.Message))" -ForegroundColor Yellow }
}

#--- ONE gate, one question: run it, skip it with a reason, or name the mode that
#--- skipped it. A failure is never cached, so the next run runs it again.
function Invoke-ProjectGate {
    param(
        [string]$Name,
        [string]$Script,
        [string]$Runner = "node",
        $Cache,
        [string[]]$ExtraArgs = @(),
        #--- exit 2 is only meaningful for the gate that defines it (P-DRAW-119's
        #--- NOT CURRENT). Every other gate's exit 2 must stay a FAIL, so this is
        #--- opt-in per call, not a blanket rule.
        [switch]$WarnOnExit2
    )
    if ($gateMode -eq "off") {
        Write-Host "  [SKIP] $Name (-Fast: gates not run)" -ForegroundColor DarkGray
        return
    }
    if (-not $gateFingerprint) { $script:gateFingerprint = Get-TreeFingerprint }
    if ($gateMode -eq "scoped" -and $Cache.ContainsKey($Name) -and $Cache[$Name] -eq $gateFingerprint) {
        Write-Host "  [SKIP] $Name (inputs unchanged since the last PASS)" -ForegroundColor DarkGray
        return
    }
    & $Runner $Script @ExtraArgs
    if ($WarnOnExit2 -and $LASTEXITCODE -eq 2) {
        #--- P-DRAW-119: A GATE THAT RAN AND SAID "NOT CURRENT" IS NOT A PASS.
        #--- check-shot-freshness.js returns 2 when the terminal's own PNGs are
        #--- missing or stale. That is not a build failure (the terminal cannot be
        #--- restarted by the build), but it MUST NOT print [PASS] — a green line
        #--- here is exactly how a mirror got read as reality for two weeks. It is
        #--- never cached either: the next run must say it again.
        Write-Host "  [WARN] $Name (ran; its verdict is NOT CURRENT — the pixels above)" -ForegroundColor Yellow
    }
    elseif ($LASTEXITCODE -ne 0) {
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
        $script:allSuccess = $false
    }
    else {
        Write-Host "  [PASS] $Name" -ForegroundColor Green
        $Cache[$Name] = $gateFingerprint
        $script:gateCacheDirty = $true
    }
}

# P-BUILD-06 RETIRED 2026-09-10 (see AGENTS.md): programmatic self-reload is
# impossible in MQL4 — manual remove & re-add remains the only code-deploy.

$resolvedCompiler = Resolve-MetaEditorPath -CustomPath $MetaEditorPath
if (-not $resolvedCompiler) {
    Write-Banner "ERROR"
    Write-Host "  MetaEditor not found." -ForegroundColor Red
    Write-Host ""
    Write-Host "  MetaTrader 4's metaeditor.exe was not found automatically." -ForegroundColor Yellow
    Write-Host "  Please provide the path using one of these methods:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    1. Command line:  .\compile-th3.ps1 -MetaEditorPath ""C:\path\to\metaeditor.exe""" -ForegroundColor White
    Write-Host "    2. Environment:   `$env:MT4_METAEDITOR = ""C:\path\to\metaeditor.exe""" -ForegroundColor White
    Write-Host ""
    Write-Host "  Common locations:" -ForegroundColor Gray
    Write-Host "    C:\Program Files (x86)\MetaTrader 4\metaeditor.exe" -ForegroundColor Gray
    Write-Host "    C:\Program Files (x86)\<BrokerName> - MetaTrader 4\metaeditor.exe" -ForegroundColor Gray
    Write-Host ""
    exit 1
}

$resolvedMql4Dir = Resolve-Mql4Directory -CustomPath $Mql4Dir
$terminalRoot = Resolve-TerminalRoot -ResolvedMql4Dir $resolvedMql4Dir

#--- P-BUILD-08: the source identity is generated BEFORE anything compiles, so the
#--- ex4 that comes out of this run carries the hash of the tree it was built from.
$buildStamp = Update-BuildHash
if (-not $buildStamp) {
    Write-Host ""
    Write-Host "  [FAIL] build stamp (every stamp this build would print is a guess)" -ForegroundColor Red
    exit 1
}

# Project paths
$PROJECTS = @{
    "workspace" = @{
        Name   = "Biotak Trigger TH3 (Workspace)"
        Source = $WORKSPACE_SOURCE
    }
    "installed" = @{
        Name   = "Biotak Trigger TH3 (Installed)"
        Source = Get-InstalledProjectSource -ResolvedMql4Dir $resolvedMql4Dir
    }
}

#--- P-BUILD-09 (2026-10-01): ONE source-unit compile, for `-SourceFile` AND for
#--- `-Tests`. The harness sweep used to re-enter this whole script once per file,
#--- so the gate layer (1.76s measured) ran nine times for nine compiles.
function Invoke-SourceUnit {
    param(
        [string]$SourceFile,
        [string]$CompilerPath,
        [string]$ResolvedMql4Dir,
        [string]$TerminalRoot
    )
    if (-not [System.IO.Path]::IsPathRooted($SourceFile)) {
        $SourceFile = Join-Path $SCRIPT_ROOT $SourceFile
    }

    # P-BUILD-03 (2026-09-25): MetaEditor resolves `#resource "\Files\Icons\x.bmp"`
    # against the SOURCE FILE's own tree, NOT the terminal's MQL4 folder. A harness
    # that lives in a subdirectory (tests\) therefore looks in <dir>\Files, and
    # without it every icon-bearing module in its chain fails with
    # `error 310: resource file ... not found` — 325 of them, measured 2026-09-25,
    # while the SAME modules compiled green from the repo root in the same run.
    # The link is created here so the documented gate ("every .mq4 must print
    # Result: 0 errors") holds on a fresh clone, where this link does not exist:
    # it is a link, never repo content (.gitignore has tests/Files).
    $srcDir = Split-Path -Parent $SourceFile
    if ($srcDir -and $srcDir -ne $SCRIPT_ROOT) {
        $linkPath = Join-Path $srcDir "Files"
        if (-not (Test-Path -LiteralPath $linkPath)) {
            try {
                New-Item -ItemType Junction -Path $linkPath -Target (Join-Path $SCRIPT_ROOT "Files") -ErrorAction Stop | Out-Null
                Write-Host "  Icon link created: $(Split-Path -Leaf $srcDir)\Files -> Files (P-BUILD-03)" -ForegroundColor DarkCyan
            }
            catch {
                Write-Host "  WARN: no icon link at $linkPath - icon modules will fail with error 310" -ForegroundColor Yellow
            }
        }
    }

    $name = [System.IO.Path]::GetFileName($SourceFile)
    return Compile-MQL4 -Name $name -SourcePath $SourceFile -CompilerPath $CompilerPath -ResolvedMql4Dir $ResolvedMql4Dir -TerminalRoot $TerminalRoot
}

if ($SourceFile -ne "") {
    # Compile specific file
    $name = [System.IO.Path]::GetFileName($SourceFile)
    $results[$name] = Invoke-SourceUnit -SourceFile $SourceFile -CompilerPath $resolvedCompiler -ResolvedMql4Dir $resolvedMql4Dir -TerminalRoot $terminalRoot
}
else {
    # Compile project(s)
    #--- P-DRAFT-01: THE "INSTALLED" PASS IS NOT A SECOND BUILD. On this machine
    #--- MQL4\Indicators\BiotakProject is a JUNCTION back to this repo, so the
    #--- installed source IS the workspace source and the installed ex4 IS the
    #--- workspace ex4 — the same file under two names. `-Project all` therefore
    #--- compiled one file twice per run, doubling the wait to tell you nothing,
    #--- and its two PASS lines looked like two independent confirmations. The
    #--- second pass now runs only when the two paths are genuinely DIFFERENT
    #--- files; otherwise it is reported as the junction it is.
    $projectsToCompile = if ($Project -eq "all") { @("workspace", "installed") } else { @($Project) }

    foreach ($proj in $projectsToCompile) {
        $info = $PROJECTS[$proj]
        if (-not $info.Source) {
            Write-Banner "Compiling: $($info.Name)"
            Write-Host "  ERROR: Could not resolve MQL4 directory for installed project." -ForegroundColor Red
            Write-Host "  Hint: Use -Mql4Dir or set MT4_MQL4_DIR env variable." -ForegroundColor Yellow
            Write-Host ""
            $results[$info.Name] = $false
            continue
        }

        $sameAsWorkspace = ($proj -eq "installed") -and
                           (Test-Path $WORKSPACE_SOURCE) -and
                           ((Get-FileHash -LiteralPath $info.Source).Hash -eq
                            (Get-FileHash -LiteralPath $WORKSPACE_SOURCE).Hash)
        if ($sameAsWorkspace) {
            Write-Host "  Skip '$($info.Name)': Indicators\BiotakProject is a junction to this repo," -ForegroundColor DarkGray
            Write-Host "        so it IS the workspace build. The ex4 above is the one the terminal loads." -ForegroundColor DarkGray
            $results[$info.Name] = $results["Biotak Trigger TH3 (Workspace)"]
            continue
        }

        $results[$info.Name] = Compile-MQL4 -Name $info.Name -SourcePath $info.Source -CompilerPath $resolvedCompiler -ResolvedMql4Dir $resolvedMql4Dir -TerminalRoot $terminalRoot
    }
}

if ($Tests) {
    #--- P-BUILD-09: every harness in ONE process. The gate layer runs once below
    #--- (and a re-run of this same tree skips what it already passed), instead of
    #--- nine times for nine files.
    $testsDir = Join-Path $SCRIPT_ROOT "tests"
    if (Test-Path -LiteralPath $testsDir) {
        foreach ($t in @(Get-ChildItem -LiteralPath $testsDir -Filter *.mq4 -File | Sort-Object Name)) {
            Write-Banner "Test: $($t.Name)"
            $results["tests\$($t.Name)"] = Invoke-SourceUnit -SourceFile $t.FullName -CompilerPath $resolvedCompiler -ResolvedMql4Dir $resolvedMql4Dir -TerminalRoot $terminalRoot
        }
    }
    else {
        Write-Host "  WARN: no tests\ folder to compile" -ForegroundColor Yellow
    }
}
elseif ($Shot) {
    # P-BUILD-10: the shot's one unit. `-Tests` already builds it, so this is only
    # for `-Shot` on its own (and it is the same compiler call either way).
    Write-Banner "Strip shot: harness"
    $shotHarness = Join-Path $SCRIPT_ROOT "tests\Biotak_StripShot_Test.mq4"
    if (Test-Path -LiteralPath $shotHarness) {
        $results["tests\Biotak_StripShot_Test.mq4"] = Invoke-SourceUnit -SourceFile $shotHarness -CompilerPath $resolvedCompiler -ResolvedMql4Dir $resolvedMql4Dir -TerminalRoot $terminalRoot
    }
    else {
        Write-Host "  WARN: tests\Biotak_StripShot_Test.mq4 is missing" -ForegroundColor Yellow
    }
}

# Final summary
Write-Banner "SUMMARY"
$allSuccess = $true
foreach ($key in $results.Keys) {
        $status = if ($results[$key]) { "PASS" } else { "FAIL"; $allSuccess = $false }
    $color  = if ($results[$key]) { "Green" } else { "Red" }
    Write-Host "  [$status] $key" -ForegroundColor $color
}

$totalTime = ((Get-Date) - $startTime).TotalSeconds.ToString("F1")
Write-Host ""
Write-Host "  Total time: ${totalTime}s" -ForegroundColor Gray
Write-Host ""
Write-Host "  MetaEditor: $resolvedCompiler" -ForegroundColor Gray
if ($resolvedMql4Dir) {
    Write-Host "  MQL4 dir:  $resolvedMql4Dir" -ForegroundColor Gray
} else {
    Write-Host "  MQL4 dir:  (not resolved - workspace compile still works)" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "  Logs folder: $PROJECT_LOG_DIR" -ForegroundColor Gray
Write-Host ""

#--- P-BUILD-08: only a build that PASSED may claim its hash beside the terminal,
#--- because that file means "the ex4 on disk IS this tree". A failed build leaves
#--- the previous stamp, and the old ex4 keeps reporting match=yes - which is true:
#--- it is still the last build this script produced.
if ($allSuccess) { Write-SourceStamp -Stamp $buildStamp -ResolvedMql4Dir $resolvedMql4Dir }
Write-Host ""

#--- P-DRAFT-01: THE RESOURCE GATE IS PART OF THE BUILD, not a thing to remember.
#--- A painted raster the unit never declared is a SILENT no-op at runtime and a
#--- green compile, which is the exact failure that shipped a panel with no plate
#--- (2026-09-29). It is the one defect the compiler cannot name, so a build that
#--- skips this check has not proved the indicator draws.
#--- P-BUILD-09: the gate cache, read once before the first gate.
$gateCache = Read-GateCache
$resGate = Join-Path $SCRIPT_ROOT "tools\check-resources.js"
if (Test-Path $resGate) {
    Write-Host ""
    Write-Host "  Resource gate (painted == #resource'd, per compiling unit):" -ForegroundColor Cyan
    Invoke-ProjectGate -Name "resource gate" -Script $resGate -Runner "node" -Cache $gateCache
}

#--- P-VIEW-06: THE LEVEL-CONTINUITY GATE IS PART OF THE BUILD. "A timeframe switch
#--- is a handoff" has been broken three times, and never in the file that states it:
#--- the prefix named the TF, the teardown deleted the family, and the adoption verdict
#--- returned with no witness and no log line. Each costume compiled green, because a
#--- delete that should not be there is a NAME, not a symbol. The check reads the six
#--- sites the handoff is made of, so a change made anywhere else cannot un-make it
#--- without failing here.
$lcGate = Join-Path $SCRIPT_ROOT "tools\check-level-continuity.js"
if (Test-Path $lcGate) {
    Write-Host ""
    Write-Host "  Level continuity gate (a switch is a handoff, not a wipe):" -ForegroundColor Cyan
    Invoke-ProjectGate -Name "level continuity gate" -Script $lcGate -Runner "node" -Cache $gateCache
}

#--- P-REG-01: THE REGRESSION REGISTER IS PART OF THE BUILD. Every entry is a defect
#--- that was fixed once and came back through a change made SOMEWHERE ELSE - the TH
#--- mask that wrote the pre-migration names (`<prefix>TH_*` while every object is
#--- born `<prefix>LBL_TH_*`), the label clear that went back to a bulk wipe, the T
#--- toggle that dropped its own owed frame, the HTF row->flag map. All of them were
#--- GREEN: the compiler only checks that names resolve, and a write to a name the
#--- chart does not carry is not an error in MT4. So the register is checked here, at
#--- the name, in every build.
$regGate = Join-Path $SCRIPT_ROOT "tools\check-regressions.js"
if (Test-Path $regGate) {
    Write-Host ""
    Write-Host "  Regression gate (fixed behaviours still owned + on the record):" -ForegroundColor Cyan
    Invoke-ProjectGate -Name "regression gate" -Script $regGate -Runner "node" -Cache $gateCache
}

#--- P-DRAW-78b: THE PANEL'S GEOMETRY GATE IS PART OF THE BUILD. A tab whose height
#--- misses the cards' law 56 + n*42 + 48 compiles clean, paints, and silently falls
#--- out of the one-baked-card branch into the composed W body — a second, wider
#--- plate beside the cards' own, which is the report this panel produced for days.
#--- The compiler cannot see it (it is arithmetic, not a symbol), so it is checked
#--- here or nowhere.
$gearGate = Join-Path $SCRIPT_ROOT "tools\check-gear-panel.py"
if ((Test-Path $gearGate) -and (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host "  Gear panel gate (every tab on the cards' baked-card law):" -ForegroundColor Cyan
    Invoke-ProjectGate -Name "gear panel gate" -Script $gearGate -Runner "python" -Cache $gateCache
}

#--- P-DRAW-93 (2026-09-30): THE ORDER GATE IS PART OF THE BUILD. A per-pass value
#--- must be WRITTEN before it is READ. `s_dsGearW` was reset inside `DrawStripGearPlace`
#--- while its first reader ran in the content pass before it (P-DRAW-91: a 592px field
#--- inside a 312 plate, two dark bars past the card), and the colour board's placement
#--- scored against the previous pass's strip/panel rect (P-DRAW-93: a board docked under
#--- a strip that had been 200px taller a frame earlier). Both were GREEN: the compiler
#--- resolves the name, the geometry gate reads the arithmetic, and both are right — only
#--- the RUN ORDER of one pass can see it. Line and regex reads of Biotak/DrawStrip_*.mqh,
#--- once per build.
$staleGate = Join-Path $SCRIPT_ROOT "tools\stale_state_check.js"
if (Test-Path $staleGate) {
    Write-Host ""
    Write-Host "  Stale state gate (a per-pass value must be written before it is read):" -ForegroundColor Cyan
    Invoke-ProjectGate -Name "stale state gate" -Script $staleGate -Runner "node" -Cache $gateCache
}

#--- P-DRAW-92: THE NAME LEDGER IS PART OF THE BUILD. A surface that paints an object
#--- must be able to DELETE it, and the compiler cannot see the difference: MT4 answers
#--- NOTHING to a write aimed at a name the chart does not carry, so an object a panel
#--- forgets to take down just stays there — over the next tab's plate, over the strip,
#--- over the chart. That is the report this gate exists for, and it found one live
#--- orphan on its first tree-wide run (the board's two page seats and their caption:
#--- painted, never pruned). Line and regex reads of Biotak/**/*.mqh, once per build.
$lifeGate = Join-Path $SCRIPT_ROOT "tools\object_lifecycle_check.js"
if (Test-Path $lifeGate) {
    Write-Host ""
    Write-Host "  Object lifecycle gate (every painted name has a destroy path):" -ForegroundColor Cyan
    Invoke-ProjectGate -Name "object lifecycle gate" -Script $lifeGate -Runner "node" -Cache $gateCache
}

#--- P-DRAW-119 (2026-10-01): THE MIRROR IS NOT THE EVIDENCE.
#--- `tools/sim-*.py` rebuild the panel from the same literals the indicator
#--- compiles, so they are right about the arithmetic and blind about what the blit
#--- really does — and the third column of `tools/before-after.html` had never been
#--- filled, so two weeks of "verified" renders were mirrors (P-DRAW-109's own class).
#--- The gate compares the PNGs the REAL paint path wrote against the newest source
#--- they are supposed to show: fresh · stale (a previous build's pixels — the exact
#--- way a mirror gets mistaken for reality) · missing. It is NEVER CACHED (its
#--- inputs include the PNGs' own mtimes, which the tree fingerprint does not hold),
#--- so every gate run states what the tree can really show, and a `-Shot` run ends
#--- strict: a capture that left a stale or partial set fails the build.
$shotGate = Join-Path $SCRIPT_ROOT "tools\check-shot-freshness.js"
if (Test-Path $shotGate) {
    Write-Host ""
    Write-Host "  Real pixels gate (the terminal's own PNGs vs the code on disk):" -ForegroundColor Cyan
    Invoke-ProjectGate -Name "real pixels gate" -Script $shotGate -Runner "node" -Cache @{} -WarnOnExit2
}

#--- P-BUILD-09: WHAT THIS RUN ACTUALLY PROVED, in one line.
if ($gateMode -eq "off") {
    Write-Host ""
    Write-Host "  GATES SKIPPED (-Fast): this build proves the names resolve, nothing more." -ForegroundColor Yellow
}
elseif ($gateCacheDirty) {
    Save-GateCache -Cache $gateCache
    Write-Host "  gate cache: this tree's fingerprint recorded for the gates that PASSED" -ForegroundColor DarkGray
}

#--- P-BUILD-10: THE REAL RENDER, AFTER THE GATES (a broken tree never gets shot).
$shotRelaunched = $false
if ($Shot) {
    Write-Host ""
    Write-Banner "STRIP SHOT (the terminal's own pixels)"
    if (-not $resolvedMql4Dir) {
        Write-Host "  [FAIL] no MQL4 folder resolved — there is nowhere to deploy the harness." -ForegroundColor Red
        $allSuccess = $false
    }
    else {
        $shotLaunch = ($RestartTerminal -and $allSuccess)
        if (-not $shotLaunch) {
            Write-Host "  prepare only (no -RestartTerminal): MT4 is left alone." -ForegroundColor DarkGray
        }
        $shotOk = Invoke-StripShot -Mql4Dir $resolvedMql4Dir -Symbol $ShotSymbol -Period $ShotPeriod -TimeoutSec $ShotTimeoutSec -Launch:$shotLaunch
        if ($shotLaunch -and $shotOk) { $shotRelaunched = $true }
        if (-not $shotOk) { $allSuccess = $false }
        #--- A SHOT RUN THAT LEFT A STALE OR PARTIAL SET IS NOT A SHOT RUN. This is
        #--- strict on purpose: `-Shot` is the run that claims "here are the real
        #--- pixels", and a claim that does not match the code on disk is the defect
        #--- (P-DRAW-119). Without -RestartTerminal nothing was captured, so nothing
        #--- is claimed — the plain (non-strict) block above already said so.
        if ($shotLaunch -and $shotOk) {
            Invoke-ProjectGate -Name "real pixels gate (strict)" -Script $shotGate -Runner "node" -Cache @{} -ExtraArgs @("--strict")
        }
        $baPage = Join-Path $SCRIPT_ROOT "tools\before-after.py"
        if ((Test-Path -LiteralPath $baPage) -and (Get-Command python -ErrorAction SilentlyContinue)) {
            & python $baPage
            Write-Host "  page: $(Join-Path $SCRIPT_ROOT 'tools\before-after.html')" -ForegroundColor Green
        }
    }
}

Write-Host ""
if ($allSuccess) {
    Write-Host "  All compilations PASSED!" -ForegroundColor Green
} else {
    Write-Host "  Some compilations FAILED." -ForegroundColor Red
}
Write-Host ""

#--- P-DRAFT-01: THE ONE DEPLOY STEP NO SCRIPT CAN DO, SAID OUT LOUD. MT4 keeps the
#--- LOADED indicator in memory: a fresh ex4 on disk changes nothing until the chart
#--- drops the instance and re-attaches, and MQL4 has no programmatic reload
#--- (P-BUILD-06). So a build that ends here has changed the FILE and nothing else,
#--- and every "my change did nothing" report since the panel work was this line
#--- being invisible. It is printed on every successful build so it is never a
#--- surprise: green build != live behaviour until you re-attach.
#--- P-BUILD-10: in `-Shot` mode this line must name the SHOT's own next step — the
#--- harness is the deployed unit there, and "re-add the indicator" would be advice
#--- about a different file than the one the run just built.
if ($Shot -and $shotRelaunched) {
    Write-Host "  NEXT: nothing — the shot run restarted the terminal on the new ex4." -ForegroundColor Yellow
    Write-Host "        render: $(Join-Path $PROJECT_LOG_DIR 'shot')\StripShot_*.png   census: StripShot-census.txt" -ForegroundColor DarkGray
}
elseif ($Shot) {
    Write-Host "  NEXT: the shot harness is deployed and the config is written; run -Shot -RestartTerminal" -ForegroundColor Yellow
    Write-Host "        (or the terminal.exe /config: line above) to get the terminal's own pixels." -ForegroundColor DarkGray
}
else {
    Write-Host "  NEXT: remove and re-add the indicator in MT4." -ForegroundColor Yellow
    Write-Host "        (a fresh ex4 is a FILE; the terminal runs what it loaded at attach)" -ForegroundColor DarkGray
}
Write-Host ""

if ($EnableLogCleanup) {
    Cleanup-BuildLogs -LogDir $PROJECT_LOG_DIR -RetentionDays $LogRetentionDays -MaxFiles $MaxBuildLogs -StateFilePath $RUNTIME_STATE_FILE
}

#--- P-BUILD-07: opt-in deploy. A green build without this flag ends with the
#--- NEXT line above (manual re-add). With -RestartTerminal, the script closes
#--- MT4 and reopens it, so every chart reloads from the new ex4 in one step.
#--- It runs ONLY on full success: a failed build never touches the terminal.
#--- It runs BEFORE the watch below, so the watch tails the FRESH log and shows
#--- the new build's own init lines — the proof the deploy landed.
if ($RestartTerminal -and $allSuccess -and -not $shotRelaunched) {
    Write-Host ""
    Write-Host "  Deploy: restarting the terminal..." -ForegroundColor Cyan
    if (-not (Restart-TradingTerminal)) { $allSuccess = $false }
    Write-Host ""
}
elseif ($shotRelaunched) {
    Write-Host "  Deploy: the terminal was restarted by the shot above — every chart (and the new ex4) is live." -ForegroundColor DarkGray
    Write-Host ""
}

if ($WatchRuntimeLogs) {
    Watch-RuntimeLogs -ResolvedMql4Dir $resolvedMql4Dir -TerminalRoot $terminalRoot -DurationSeconds $WatchSeconds -PollMs $WatchPollMs
}

# Return exit code
exit $(if ($allSuccess) { 0 } else { 1 })

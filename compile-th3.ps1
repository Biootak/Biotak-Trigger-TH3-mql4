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

    [switch]$RestartTerminal
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

function Restart-TradingTerminal {
    #--- P-BUILD-07: THE DEPLOY LOOP, CLOSED. MT4 runs what it loaded at attach;
    #--- a fresh ex4 is a file until the terminal restarts or the indicator is
    #--- removed and re-added. Re-add is manual and per-chart; a restart reloads
    #--- EVERY chart from the new ex4 in one step. Opt-in only (-RestartTerminal):
    #--- killing the terminal also stops anything else it hosts, so this never
    #--- runs unless asked. Each instance is relaunched with its OWN executable
    #--- path and command line (portable/datapath flags survive), so the same
    #--- data folder — and the same charts — come back.
    $procs = Get-WmiObject Win32_Process -Filter "Name='terminal.exe'" -ErrorAction SilentlyContinue
    if (-not $procs) {
        Write-Host "  No running terminal.exe found; nothing to restart." -ForegroundColor Yellow
        return $true
    }
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
    if ($starts.Count -eq 0) {
        Write-Host "  Terminal processes found but their paths are unreadable; not restarting." -ForegroundColor Red
        return $false
    }
    Write-Host "  Restarting $($starts.Count) terminal process(es) so the new ex4 loads..." -ForegroundColor Yellow
    foreach ($s in $starts) { Write-Host "    will relaunch: $($s.Exe) $($s.Args)" -ForegroundColor DarkGray }
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
    foreach ($s in $starts) {
        if ($s.Args) { Start-Process -FilePath $s.Exe -ArgumentList $s.Args }
        else { Start-Process -FilePath $s.Exe }
    }
    Write-Host "  Terminal restarted. Charts come back on their own; every indicator reloads from the new ex4." -ForegroundColor Green
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

if ($SourceFile -ne "") {
    # Compile specific file
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
    $results[$name] = Compile-MQL4 -Name $name -SourcePath $SourceFile -CompilerPath $resolvedCompiler -ResolvedMql4Dir $resolvedMql4Dir -TerminalRoot $terminalRoot
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

#--- P-DRAFT-01: THE RESOURCE GATE IS PART OF THE BUILD, not a thing to remember.
#--- A painted raster the unit never declared is a SILENT no-op at runtime and a
#--- green compile, which is the exact failure that shipped a panel with no plate
#--- (2026-09-29). It is the one defect the compiler cannot name, so a build that
#--- skips this check has not proved the indicator draws.
$resGate = Join-Path $SCRIPT_ROOT "tools\check-resources.js"
if (Test-Path $resGate) {
    Write-Host ""
    Write-Host "  Resource gate (painted == #resource'd, per compiling unit):" -ForegroundColor Cyan
    & node $resGate
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [FAIL] resource gate" -ForegroundColor Red
        $allSuccess = $false
    }
    else {
        Write-Host "  [PASS] resource gate" -ForegroundColor Green
    }
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
    & python $gearGate
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [FAIL] gear panel gate" -ForegroundColor Red
        $allSuccess = $false
    }
    else {
        Write-Host "  [PASS] gear panel gate" -ForegroundColor Green
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
Write-Host "  NEXT: remove and re-add the indicator in MT4." -ForegroundColor Yellow
Write-Host "        (a fresh ex4 is a FILE; the terminal runs what it loaded at attach)" -ForegroundColor DarkGray
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
if ($RestartTerminal -and $allSuccess) {
    Write-Host ""
    Write-Host "  Deploy: restarting the terminal..." -ForegroundColor Cyan
    if (-not (Restart-TradingTerminal)) { $allSuccess = $false }
    Write-Host ""
}

if ($WatchRuntimeLogs) {
    Watch-RuntimeLogs -ResolvedMql4Dir $resolvedMql4Dir -TerminalRoot $terminalRoot -DurationSeconds $WatchSeconds -PollMs $WatchPollMs
}

# Return exit code
exit $(if ($allSuccess) { 0 } else { 1 })

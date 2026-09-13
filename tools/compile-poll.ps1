param(
  [string]$Source = "C:\Users\Bioootak\AppData\Roaming\MetaQuotes\Terminal\A1660DA4CB596E740BE3B3233E577E1B\MQL4\Indicators\BiotakProject\Biotak Trigger TH3.mq4",
  [string]$Log    = "C:\Users\Bioootak\AppData\Roaming\MetaQuotes\Terminal\A1660DA4CB596E740BE3B3233E577E1B\MQL4\Indicators\BiotakProject\build-logs\agent-compile.log",
  [int]$TimeoutSec = 60
)
# P-BUILD-07: MetaEditor is SINGLE-INSTANCE. A CLI /compile against an already
# running MetaEditor is FORWARDED to that window; the launcher exits in ~0.07s
# with no exit code and no log, so `Start-Process -Wait` proves nothing. The
# running window compiles ASYNCHRONOUSLY, so poll the log's timestamp instead.
#
# NB: do NOT Remove-Item the stale log first -- the sandbox's safe-delete guard
# blocks it (SAFE_DELETE_BULK_GUARD_ERROR). Compare LastWriteTime instead.
foreach($n in @('http_proxy','HTTP_PROXY','https_proxy','HTTPS_PROXY','no_proxy','NO_PROXY')){
  [System.Environment]::SetEnvironmentVariable($n, $null, 'Process')
}
$me  = 'C:\Program Files (x86)\AMarkets - MetaTrader 4\metaeditor.exe'
$ex4 = [System.IO.Path]::ChangeExtension($Source, '.ex4')
$ex4Before = if(Test-Path $ex4) { (Get-Item $ex4).LastWriteTime } else { [datetime]::MinValue }
$logBefore = if(Test-Path $Log) { (Get-Item $Log).LastWriteTime } else { [datetime]::MinValue }

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$p = Start-Process -FilePath $me -ArgumentList ("/compile:`"$Source`"", "/log:`"$Log`"") -PassThru
$launcherMs = $sw.ElapsedMilliseconds

# poll: the log is rewritten (mtime advances) and ends with a "Result:" line
$deadline = (Get-Date).AddSeconds($TimeoutSec)
$fresh = $false
$text  = ''
while((Get-Date) -lt $deadline){
  Start-Sleep -Milliseconds 500
  if(Test-Path $Log){
    $li = Get-Item $Log
    if($li.LastWriteTime -gt $logBefore -and $li.Length -gt 0){
      # metaeditor.exe keeps the log OPEN while it writes, and ReadAllText then
      # throws "being used by another process" - which used to abort the whole
      # script mid-compile. An unreadable log is just "not ready yet".
      $t = ''
      try { $t = [System.IO.File]::ReadAllText($Log, [System.Text.Encoding]::Unicode) }
      catch { continue }
      if($t -match 'Result:'){ $fresh = $true; $text = $t; break }
    }
  }
}
$sw.Stop()

$out = @()
$out += "launcher returned in ${launcherMs}ms (single-instance forwarding)"
$out += "fresh log: $fresh after $($sw.ElapsedMilliseconds)ms"
$ex4After = if(Test-Path $ex4) { (Get-Item $ex4).LastWriteTime } else { [datetime]::MinValue }
$out += "ex4 before=$ex4Before after=$ex4After rebuilt=$($ex4After -gt $ex4Before)"
$out += "---- log ----"
if($fresh){
  $out += ($text -split "`r?`n" | Where-Object { $_ -notmatch 'information: including' -and $_.Trim() -ne '' })
} elseif(Test-Path $Log){
  $out += "(log not refreshed -- MetaEditor may be busy)"
} else { $out += "(no log written)" }
$out | Out-File -Encoding UTF8 "C:\Users\Bioootak\Desktop\Trading\Biotak-Trigger-TH3-mql4\build-logs\_result1.txt"

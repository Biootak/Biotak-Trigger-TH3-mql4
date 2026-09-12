param(
  [string]$Source = "C:\Users\Bioootak\AppData\Roaming\MetaQuotes\Terminal\A1660DA4CB596E740BE3B3233E577E1B\MQL4\Indicators\BiotakProject\Biotak Trigger TH3.mq4",
  [string]$Log    = "C:\Users\Bioootak\AppData\Roaming\MetaQuotes\Terminal\A1660DA4CB596E740BE3B3233E577E1B\MQL4\Indicators\BiotakProject\build-logs\agent-compile.log"
)
# P-BUILD-06: the host process carries both casings of the proxy vars and
# Start-Process builds a case-insensitive env dictionary. Clear them first.
foreach($n in @('http_proxy','HTTP_PROXY','https_proxy','HTTPS_PROXY','no_proxy','NO_PROXY')){
  [System.Environment]::SetEnvironmentVariable($n, $null, 'Process')
}
$me = 'C:\Program Files (x86)\AMarkets - MetaTrader 4\metaeditor.exe'
if(Test-Path $Log) { Remove-Item $Log -Force }
$p = Start-Process -FilePath $me -ArgumentList ("/compile:`"$Source`"", "/log:`"$Log`"") -Wait -PassThru
$text = ''
if(Test-Path $Log) { $text = [System.IO.File]::ReadAllText($Log, [System.Text.Encoding]::Unicode) }
$lines = $text -split "`r?`n" | Where-Object { $_ -notmatch 'information: including' -and $_.Trim() -ne '' }
$lines | ForEach-Object { Write-Output $_ }
Write-Output ("metaeditor exit=" + $p.ExitCode)

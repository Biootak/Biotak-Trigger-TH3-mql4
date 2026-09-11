# clean-9router-hosts.ps1 -- remove the leftovers of a 9router run that was
# KILLED instead of STOPPED (see AGENTS.md P-ENV-01).
#
# WHY THIS EXISTS
# 9router intercepts model traffic with a local MITM: it writes
#   127.0.0.1 <api host>
# lines into the Windows hosts file, mints leaf certificates from its own root
# CA, and listens on :443. `9router stop` removes the hosts lines and runs
# `reg delete HKCU\Environment /V NODE_EXTRA_CA_CERTS`. Killing it removes
# NOTHING, so the machine is left in a half-state: the API hosts still resolve
# to 127.0.0.1 while nothing answers on :443, the TLS layer fails, and any
# model stream on that path dies mid-response with
#   TypeError: unknown certificate verification error
#
# This script finishes that stop. It is IDEMPOTENT and NARROW: it only touches
# lines that map one of 9router's own hostnames to a loopback address, so a
# legitimate hosts entry you added yourself is never removed.
#
# The hosts file needs Administrator. The env var is per-user (HKCU), which is
# the same profile under a normal same-user UAC elevation.
#
# Usage (elevated):
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\clean-9router-hosts.ps1
# Dry run:
#   ... -WhatIfOnly
#
# NOTE: keep this file ASCII-only (P-TOOL-05) -- PowerShell 5.1 reads a .ps1
# without a BOM as ANSI and a stray UTF-8 dash cascades into fake parse errors.

param(
  [switch]$WhatIfOnly,
  [string]$Log = ''
)

$ErrorActionPreference = 'Stop'

# 9router's managed host list (from its own source: the DNS/hosts table it
# rewrites on start). Extend here if a future 9router adds another host.
$Managed = @(
  'api.anthropic.com',
  'api.individual.githubcopilot.com',
  'cloudcode-pa.googleapis.com',
  'daily-cloudcode-pa.googleapis.com'
)

if (-not $Log) {
  $repo = Split-Path -Parent $PSScriptRoot
  $Log = Join-Path $repo 'build-logs\9router-cleanup.log'
}
$logDir = Split-Path -Parent $Log
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

$lines = New-Object System.Collections.Generic.List[string]
function Say([string]$m) {
  Write-Host $m
  $lines.Add($m)
}

$hosts = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
Say ("[9R] hosts file: " + $hosts)
Say ("[9R] elevated  : " + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))

# ---- 1. hosts file ---------------------------------------------------------
$raw = [System.IO.File]::ReadAllText($hosts)
$sep = "`r`n"
$all = $raw -split "`r`n|`n"

# a loopback target for one of 9router's hosts, active (not commented out)
$rx = '^\s*(127\.0\.0\.1|::1|localhost)\s+(' + (($Managed | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')\s*$'

$kept    = New-Object System.Collections.Generic.List[string]
$removed = New-Object System.Collections.Generic.List[string]
foreach ($ln in $all) {
  $probe = $ln
  if ($probe.Contains("`r")) { $probe = $probe.Replace("`r", '') }
  if ($probe -match $rx) { $removed.Add($probe) } else { $kept.Add($ln) }
}

if ($removed.Count -eq 0) {
  Say '[9R] hosts: nothing to remove (already clean).'
} else {
  foreach ($r in $removed) { Say ("[9R] hosts: REMOVE  " + $r.Trim()) }
  if ($WhatIfOnly) {
    Say ("[9R] dry run -- hosts file NOT written (" + $removed.Count + " line(s) would go).")
  } else {
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $backup = Join-Path (Split-Path -Parent $hosts) ("hosts.9router-backup-" + $stamp)
    Copy-Item -LiteralPath $hosts -Destination $backup -Force
    Say ("[9R] hosts: backup -> " + $backup)

    $out = ($kept -join $sep)
    # keep the file ending in exactly one newline
    $out = $out.TrimEnd("`r", "`n") + $sep
    [System.IO.File]::WriteAllText($hosts, $out, (New-Object System.Text.UTF8Encoding($false)))
    Say ("[9R] hosts: wrote " + $removed.Count + " line(s) removed, " + $kept.Count + " kept.")
  }
}

# ---- 2. the per-user CA variable ------------------------------------------
$ca = [Environment]::GetEnvironmentVariable('NODE_EXTRA_CA_CERTS', 'User')
if ([string]::IsNullOrEmpty($ca)) {
  Say '[9R] NODE_EXTRA_CA_CERTS (User): already unset.'
} elseif ($WhatIfOnly) {
  Say ("[9R] dry run -- would unset NODE_EXTRA_CA_CERTS (User) = " + $ca)
} else {
  # Only clear it while 9router is genuinely NOT listening on :443. If it IS
  # running, the variable is *correct* state and must be left alone.
  $listening = $false
  try {
    $listening = [bool](Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction Stop)
  } catch { $listening = $false }
  if ($listening) {
    Say '[9R] port 443 IS listening -- 9router looks active, leaving the CA variable alone.'
  } else {
    [Environment]::SetEnvironmentVariable('NODE_EXTRA_CA_CERTS', $null, 'User')
    Say ("[9R] NODE_EXTRA_CA_CERTS (User): unset (was " + $ca + ")")
  }
}

# ---- 3. report -------------------------------------------------------------
$stillListening = $false
try { $stillListening = [bool](Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction Stop) } catch {}
Say ("[9R] port 443 listening now: " + $stillListening)
Say '[9R] done.'

Set-Content -LiteralPath $Log -Value $lines -Encoding ASCII

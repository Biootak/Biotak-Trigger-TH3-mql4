@echo off
rem ---------------------------------------------------------------------------
rem One-click cleanup after 9router was KILLED instead of stopped (P-ENV-01).
rem
rem 9router redirects its API hosts to 127.0.0.1 through the Windows hosts file
rem and sets a per-user NODE_EXTRA_CA_CERTS. `9router stop` undoes both; a kill
rem undoes neither, so requests keep going to 127.0.0.1:443 where nothing
rem listens -- the TLS layer fails and model streams die mid-response with
rem "unknown certificate verification error".
rem
rem Just double-click this file and accept the UAC prompt (it re-launches itself
rem elevated because the hosts file is protected). It backs the hosts file up
rem first and only removes 9router's own hostnames, so it is safe to re-run.
rem ---------------------------------------------------------------------------
setlocal

net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting administrator rights...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\clean-9router-hosts.ps1"

echo.
echo Finished. The same report was written to build-logs\9router-cleanup.log
echo.
pause

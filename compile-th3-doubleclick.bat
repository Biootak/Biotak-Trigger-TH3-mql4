@echo off
REM TH3 one-double-click build (Full workspace+installed AND Lite).
REM Solves the "black window flashes and closes" problem: runs PowerShell
REM with Bypass (double-click uses Restricted and dies instantly) and PAUSEs
REM at the end so results stay visible. Needs MANUAL remove/re-add on chart
REM afterwards (P-BUILD-06: MQL4 cannot hot-swap code).
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0compile-th3.ps1" -Project all
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0compile-th3.ps1" -SourceFile "Biotak Trigger TH3 Lite.mq4"
echo.
echo === Done. Press any key to close. Deploy with remove/re-add on chart. ===
pause >nul

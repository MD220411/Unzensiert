@echo off
rem Double-click to install claude-local, or to repair an install. Details: README.md
rem Arguments are passed on, e.g.  Install.cmd -Plan   (only show what would happen)
setlocal
set "NoDefaultCurrentDirectoryInExePath=1"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install.ps1" %*
echo.
pause

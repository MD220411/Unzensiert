@echo off
rem Double-click to remove claude-local again. Asks before deleting anything. Details: README.md
setlocal
set "NoDefaultCurrentDirectoryInExePath=1"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Uninstall.ps1" %*
echo.
pause

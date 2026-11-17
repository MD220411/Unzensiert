@echo off
rem Double-click to remove claude-local again. Asks before deleting anything. Details: README.md
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Uninstall.ps1" %*
echo.
pause

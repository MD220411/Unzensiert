@echo off
rem Double-click to install claude-local, or to repair an install. Details: README.md
rem Arguments are passed on, e.g.  Install.cmd -Plan   (only show what would happen)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install.ps1" %*
echo.
pause

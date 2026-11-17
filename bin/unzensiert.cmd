@echo off
rem Wrapper so that `unzensiert` works from any terminal (cmd, PowerShell, VS Code).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\unzensiert.ps1" %*

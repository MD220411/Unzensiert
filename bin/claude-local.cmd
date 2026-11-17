@echo off
rem Wrapper so that `claude-local` works from any terminal (cmd, PowerShell, VS Code).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\claude-local.ps1" %*

@echo off
rem Wrapper so that `claude-local` works from any terminal (cmd, PowerShell, VS Code).
rem cmd looks into the current folder before PATH: a file powershell.cmd in a foreign project would
rem run instead of the real program. Hence the full path, and no search in the current folder.
setlocal
set "NoDefaultCurrentDirectoryInExePath=1"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\claude-local.ps1" %*

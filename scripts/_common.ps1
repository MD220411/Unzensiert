# Entry point for the shared helpers. Every script starts with:
#   . "$PSScriptRoot\_common.ps1"
# The helpers themselves live in scripts\lib\, one file per topic:
#   lib\Config.ps1   reads config\*.json (server, models, agent)
#   lib\Server.ps1   starts, stops and queries llama-server
#   lib\Measure.ps1  speed, tool-call and GPU-memory measurements
#   lib\Session.ps1  running claude-local sessions; frees the GPU memory after the last one
#   lib\Safety.ps1   safety guard for tool calls of the local model, git as the way back
#   lib\Quality.ps1 closing check (Stop hook) and the commands /feature, /bugfix, /pruefen
#   lib\Review.ps1   second look: a second local model checks the uncommitted change
#   lib\Tasks.ps1    benchmark tasks: work copies and the hidden check
#   lib\Projects.ps1 new projects from the templates in templates\projekt\
#   lib\Style.ps1    the look (config\style.json, config\styles\): colours, terminal tint,
#                    readings for prompt and status line; pictures made of characters in
#                    lib\CharArt.ps1 (both read their config themselves, see the header)
# Keep these files ASCII-only: Windows PowerShell 5.1 reads BOM-less files as ANSI.

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\Config.ps1"
. "$PSScriptRoot\lib\Server.ps1"
. "$PSScriptRoot\lib\Measure.ps1"
. "$PSScriptRoot\lib\Session.ps1"
. "$PSScriptRoot\lib\Safety.ps1"
. "$PSScriptRoot\lib\Quality.ps1"
. "$PSScriptRoot\lib\Review.ps1"
. "$PSScriptRoot\lib\Tasks.ps1"
. "$PSScriptRoot\lib\Projects.ps1"
. "$PSScriptRoot\lib\Style.ps1"

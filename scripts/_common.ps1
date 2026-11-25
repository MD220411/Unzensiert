# Entry point for the shared helpers. Every script starts with:
#   . "$PSScriptRoot\_common.ps1"
# The helpers themselves live in scripts\lib\, one file per topic:
#   lib\Git.ps1      git by its full path and without programs of a repository; the search order
#                    for programs (no program from the current folder)
#   lib\Config.ps1   reads config\*.json (server, models, agent) and config\machine.json
#   lib\Machine.ps1  this machine: graphics cards, memory, disk space, programs, setups
#   lib\FolderRights.ps1 install and program folder only for the user, SYSTEM, administrators
#   lib\Download.ps1 downloads with resume and checksum (llama.cpp, model files)
#   lib\Planner.ps1  computes how each model is best spread over cards and main memory
#   lib\Dialog.ps1   steps, notes and yes/no questions of the installer and uninstaller
#   lib\Server.ps1   starts, stops and queries llama-server
#   lib\Measure.ps1  speed, tool-call and GPU-memory measurements
#   lib\Session.ps1  running claude-local sessions; frees the GPU memory after the last one
#   lib\Safety.ps1   safety guard for tool calls of the local model, git as the way back
#   lib\Quality.ps1 closing check (Stop hook) and the commands /feature, /bugfix, /review
#   lib\Review.ps1   second look: a second local model checks the uncommitted change
#   lib\Tasks.ps1    benchmark tasks: work copies and the hidden check
#   lib\Projects.ps1 new projects from the templates in templates\project\
#   lib\Style.ps1    the look (config\style.json, config\styles\): colours, terminal tint,
#                    readings for prompt and status line; pictures made of characters in
#                    lib\CharArt.ps1 (both read their config themselves, see the header)
#   lib\Agent*.ps1   the agent Unzensiert (scripts\unzensiert.ps1, docs\unzensiert.md):
#                    AgentApi     JSON and the streamed chat request to llama-server
#                    AgentTools   the tools Bash, PowerShell, Read, Edit, Write, Glob, Grep
#                    AgentPlan    task list, questions, the plan, plan mode; which own tools
#                    AgentWeb     WebSearch and WebFetch, web pages as text
#                    AgentPrompt  system prompt with the instructions of the project
#                    Trust        which folder the user trusts, with what (hooks\TrustRules.ps1)
#                    CommandRules what a command line is made of: does it only read, is it covered
#                                 by a rule, does it only change files of the project
#                    AgentSession messages, saved conversations, size of the context
#                    Undo         /undo: the project folder kept before and after each request
#                    Sandbox      commands of the model as a Windows account of their own
#                    AgentUi      the terminal: welcome, activity line, notes, input, the end
#                                 of a request and of the session
#                    AgentUiBar   the status bar at the bottom, Write-UiOut for all output
#                    AgentUiMarkdown  the answer: Markdown, word wrap, colours of code
#                    AgentUiTools the tool calls, diffs of changes, the question before a call
#                    AgentUiPlan  the task list, the frame of a question, the plan to approve
#                    AgentLoop    one request: model, guard, permissions, tools, closing check
#                    AgentRepl    the conversation, commands with a slash, the -p run
#   lib\Update.ps1   automatic updates from the releases on GitHub (config\updates.json)
# Keep these files ASCII-only: Windows PowerShell 5.1 reads BOM-less files as ANSI.

$ErrorActionPreference = 'Stop'

# cmd.exe looks into the current folder before PATH, so a file git.cmd or powershell.cmd in a
# foreign project would run instead of the real program. With this variable it does not, here
# and in everything started from here (docs\security.md).
$env:NoDefaultCurrentDirectoryInExePath = '1'
# and no entry of PATH that depends on the folder this was started in (., .\node_modules\.bin)
if ($env:PATH -match '(^|;)\s*"?(\.|\s*;)') { $env:PATH = (@($env:PATH.Split(';') | Where-Object { $_.Trim() -and $_.Trim().Trim('"') -notmatch '^\.' }) -join ';') }

. "$PSScriptRoot\lib\Git.ps1"
. "$PSScriptRoot\hooks\TrustRules.ps1"
. "$PSScriptRoot\lib\Config.ps1"
. "$PSScriptRoot\lib\Machine.ps1"
. "$PSScriptRoot\lib\FolderRights.ps1"
. "$PSScriptRoot\lib\Download.ps1"
. "$PSScriptRoot\lib\Planner.ps1"
. "$PSScriptRoot\lib\Dialog.ps1"
. "$PSScriptRoot\lib\Server.ps1"
. "$PSScriptRoot\lib\Measure.ps1"
. "$PSScriptRoot\lib\Session.ps1"
. "$PSScriptRoot\lib\Safety.ps1"
. "$PSScriptRoot\lib\Quality.ps1"
. "$PSScriptRoot\lib\Review.ps1"
. "$PSScriptRoot\lib\Tasks.ps1"
. "$PSScriptRoot\lib\Projects.ps1"
. "$PSScriptRoot\lib\Style.ps1"
. "$PSScriptRoot\lib\AgentApi.ps1"
. "$PSScriptRoot\lib\AgentTools.ps1"
. "$PSScriptRoot\lib\AgentPlan.ps1"
. "$PSScriptRoot\lib\AgentWeb.ps1"
. "$PSScriptRoot\lib\Trust.ps1"
. "$PSScriptRoot\lib\CommandRules.ps1"
. "$PSScriptRoot\lib\AgentPrompt.ps1"
. "$PSScriptRoot\lib\AgentSession.ps1"
. "$PSScriptRoot\lib\Undo.ps1"
. "$PSScriptRoot\lib\Sandbox.ps1"
. "$PSScriptRoot\lib\AgentUi.ps1"
. "$PSScriptRoot\lib\AgentUiBar.ps1"
. "$PSScriptRoot\lib\AgentUiMarkdown.ps1"
. "$PSScriptRoot\lib\AgentUiTools.ps1"
. "$PSScriptRoot\lib\AgentUiPlan.ps1"
. "$PSScriptRoot\lib\AgentLoop.ps1"
. "$PSScriptRoot\lib\AgentRepl.ps1"
. "$PSScriptRoot\lib\Update.ps1"

# install folder and projects folder for the hooks, which Claude Code starts as processes
# of their own (lib\Config.ps1, Publish-ConfigEnvironment)
Publish-ConfigEnvironment

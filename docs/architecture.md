# Architecture

## Goal

A coding agent that is operated like Claude Code but runs completely locally: without a token
limit, without the cloud and with a model that does not refuse requests. The project should
stay maintainable for a long time: every setting has exactly one place, every script exactly
one job.

## The layers

```
Terminal / VS Code
   │  unzensiert                   bin\unzensiert.cmd → scripts\unzensiert.ps1
   ▼
Unzensiert (own agent)             reads and writes files, runs commands (scripts\lib\Agent*.ps1)
   │  OpenAI-compatible API        http://127.0.0.1:8080/v1/chat/completions
   ▼
llama-server (router)              backend: takes requests, starts one process per model
   │  one child process per model
   ▼
Model profile, e.g. local-coder    entry in config\models.json (+ config\machine.json)
   └─ GGUF file                    <installRoot>\models\*.gguf
```

For comparison there is a second way to the same server: `claude-local`
(`bin\claude-local.cmd` → `scripts\claude-local.ps1`) starts Claude Code, which talks through
the Anthropic-compatible interface `/v1/messages`. Both agents share guard, closing check,
working rules, workflows and model choice.

Below that lies the setup: `Install.cmd` or the one-liner `install.ps1` starts
`scripts\Install.ps1`, which recognises the computer (`lib\Machine.ps1`), downloads llama.cpp
and the fitting model (`lib\Download.ps1`) and writes the values of the computer into
`config\machine.json` ([setup.md](setup.md)).

Continue (chat and autocomplete in the editor) talks to the same server through its
OpenAI-compatible interface.

Every layer can be replaced on its own:

| Layer | Current | Where to change | Description |
|---|---|---|---|
| Agent | Unzensiert; for comparison Claude Code through `claude-local` | `config\unzensiert.json`, `config\agent.json`, `scripts\unzensiert.ps1`, `scripts\claude-local.ps1` | [unzensiert.md](unzensiert.md), [agent.md](agent.md) |
| Backend | llama.cpp (`llama-server`) | `config\server.json` | [backend.md](backend.md) |
| Models | Qwen 3.6 27B and 35B-A3B uncensored, Qwen 3.8 27B uncensored | `config\models.json` | [models.md](models.md) |

## Folder structure

```
Install.cmd          install or repair with a double click (starts scripts\Install.ps1)
Uninstall.cmd        remove again (scripts\Uninstall.ps1)
install.ps1          one-line install: gets the newest release (otherwise main), starts scripts\Install.ps1
VERSION              version of the program; releases on GitHub carry the tag vX.Y.Z
bin\                 commands for the PATH (unzensiert.cmd, claude-local.cmd)
config\              all settings
  server.json          llama-server: version, packages per graphics card, address, limits
  models.json          model profiles: file, download, context, sampling
  setups.json          hardware tiers: which model the installer suggests for how much graphics memory
  planner.json         planner: reserves, context sizes, tolerance (planner.md)
  machine.json         values of this computer (folders, computed split, default model, calibration); from the installer, not in the repository
  agent.json           both agents: default model, short names, model choice, rules, closing check, tools
  unzensiert.json      Unzensiert: rights, context, time limits, commands without a question (unzensiert.md)
  unzensiert-prompt.md system prompt of Unzensiert
  unzensiert-texts.json texts of the terminal of Unzensiert (style.md)
  updates.json         automatic updates from the releases on GitHub
  coding-rules.md      working rules the local model gets in every session
  closing-check.md     reminder of the closing check (test, README, settings, cleanup)
  second-look.md       review instructions for the second look (a second model checks the diff)
  workflows\           workflows /feature, /bugfix, /review (also a plugin for claude-local: /local:feature ...)
  projects.json        New-Project.ps1: templates, languages, target folder
  templates\           chat templates (Jinja) for models whose own template does not fit
  continue.config.yaml configuration of the VS Code extension Continue
  benchmark.json       which profiles and tasks the benchmark measures
  guard.json           guard rules: what the local model may not do or only after a question (security.md)
  style.json           which look applies (style.md)
  styles\              per style colours, glyphs, texts, font for pictures of characters: breakout.json, nightshift.json
scripts\             one script per job (setting up, starting, testing, measuring)
  style\               Shell.ps1 (prompt, greeting), Statusline.ps1 (status line of Claude Code)
  lib\                 shared building blocks: Config.ps1, Machine.ps1, Download.ps1, Planner.ps1, Dialog.ps1, Server.ps1,
                       Measure.ps1, Session.ps1, Safety.ps1, Quality.ps1, Review.ps1, Tasks.ps1, Projects.ps1,
                       Style.ps1, CharArt.ps1, Update.ps1; the agent Unzensiert in AgentApi.ps1, AgentTools.ps1,
                       AgentPrompt.ps1, AgentSession.ps1, AgentUi.ps1, AgentUiMarkdown.ps1, AgentUiTools.ps1,
                       AgentLoop.ps1, AgentRepl.ps1
  hooks\               GuardRules.ps1: rules of the guard, which Unzensiert checks in its own process;
                       Guard-Tool.ps1: guard that Claude Code starts before every tool call;
                       Check-Stop.ps1: closing check before the model ends an answer;
                       HookEnvironment.ps1: install and project folder for both
  _common.ps1          loads lib\; every script begins with it
benchmark\tasks\     tasks for the agent benchmark (template, prompt, check, reference solution)
benchmark\lib\       rulecheck.py: measures in the checks whether the working rules were followed
benchmark\overlays\  additions that equip a task like a project made from the template
templates\project\   templates for new projects (shared\, python\, powershell\), see projects.md
tests\               test cases for the scripts (guard-cases.json for Test-Guard.ps1; agent-design.json,
                     a sample session for Show-AgentDesign.ps1 and Test-Agent.ps1)
docs\                documentation
logs\                measurements (results.jsonl, model-tests.log)
```

Outside the repository, because large or generated. The place is `installRoot`: the
installer suggests `claude-local` on the drive with the most room and remembers it in
`config\machine.json`; without that file `%LOCALAPPDATA%\claude-local` from
`config\server.json` applies.

```
<installRoot>\
  b12433\            programs of a llama.cpp version (one folder per version, package.txt names the package)
  models\            GGUF files
  run\models.ini     model list for the server, generated from config\models.json
  run\sessions\      marks of the running sessions (unzensiert and claude-local)
  run\update-check.json  when a release was last looked for
  sessions\          saved conversations of Unzensiert, one folder per project folder
  unzensiert-history.txt  earlier input in Unzensiert
  run\stop\          state of the closing check per session
  run\api-key.txt    key of the server (secret, created at the first start)
  logs\server.log    log of the server
  logs\guard.log     what the guard blocked or asked about
  downloads\         downloaded archives
```

## The agent Unzensiert: files, pitfalls, tests, releases

Moved here from `unzensiert.md` on 2026-11-18, when the development material became private.

| File | Content |
|---|---|
| `scripts\unzensiert.ps1`, `bin\unzensiert.cmd` | starter: arguments, update, model, server, session |
| `scripts\lib\AgentApi.ps1` | JSON (JavaScriptSerializer of .NET, much faster than `ConvertTo-Json`) and the streamed request |
| `scripts\lib\AgentTools.ps1` | the tools |
| `scripts\lib\AgentPrompt.ps1` | system prompt with project instructions |
| `scripts\lib\AgentSession.ps1` | messages, saved conversations, size of the context |
| `scripts\lib\AgentUi.ps1` | terminal: texts, colours, welcome, activity line, title and progress of the tab, notes, input (PSReadLine), status line, overviews, end of a request, farewell |
| `scripts\lib\AgentUiMarkdown.ps1` | the answer: Markdown, wrapping, tables, colours of code |
| `scripts\lib\AgentUiTools.ps1` | tools, diffs, questions |
| `config\unzensiert-texts.json` | texts of the terminal |
| `scripts\Show-AgentDesign.ps1`, `tests\agent-design.json` | all elements of the terminal with a sample session, without a model |
| `scripts\lib\AgentLoop.ps1` | one request: model, guard, rights, tools, closing check, context |
| `scripts\lib\AgentRepl.ps1` | conversation, slash commands, one-off run, arguments |
| `scripts\lib\Update.ps1` | automatic updates |
| `scripts\hooks\GuardRules.ps1` | rules of the guard, shared with the hook for Claude Code; Unzensiert checks in its own process (2.7 ms per call instead of 280 ms for a hook process, measured) |
| `scripts\Test-Agent.ps1` | checks without a model (about 5 s), `-WithModel` with a small task |
| `scripts\New-Release.ps1` | publish a release |

Deliberate peculiarities of PowerShell 5.1 the code takes care of: lists come back from
functions with a leading comma (otherwise a list with one element becomes that element; the
call then does not also stand in `@(...)`, that would give a list in a list), indices of a
two-dimensional array with expressions (`$t[($i + 1), $j]`) go into variables first, because
PowerShell cannot read them as the argument of a method, data for the server contains no
values of cmdlets (`New-Object`, `Join-Path`, `Get-Date` wrap them in a PSObject the
serialiser does not know), contents of files are compared with `-ceq` (`-eq` ignores upper and
lower case; an edit from `true` to `True` therefore counted as "nothing to change" until
2026-11-18), variable names are case-insensitive (`$n` is the same as a parameter `$N`, so a
local variable can overwrite a parameter), and child processes start through
`Start-ChildProcess` (`lib\Machine.ps1`), because .NET otherwise writes a byte order mark into
their input on a UTF-8 console.

**Tests of the terminal:**

- **Operation in the terminal** (keys, input line, questions) is only checked by the test
  scripts up to the output; no script can simulate key presses. One-off runs and the
  benchmark are measured.

**Releases:**

- **Publishing a release** (only for maintaining the repository):
  `scripts\New-Release.ps1 -Version 1.1.0 -Notes "..."` checks working state, branch and tag,
  runs the check scripts, writes `VERSION`, commits, sets the tag, pushes and creates the
  release with `gh`; `-DryRun` only shows what would happen.

## Principles

- **Configuration lives in `config\`, not in scripts.** Scripts read all values through
  `scripts\lib\Config.ps1`. Whoever wants to change something changes a file in `config\`
  and restarts the server.
- **Project and computer kept apart.** The files in `config\` apply on every computer. What
  is only true for one computer (folders, split across particular cards, default model) is in
  `config\machine.json`, not in the repository. No fixed drives, card names or card splits in
  the shared files; `Test-Install.ps1` checks that for the model profiles.
- **One source per fact.** Address and port are only in `server.json`, models only in
  `models.json`. Exception: `continue.config.yaml` repeats address and model names, because
  Continue cannot read the other files; `Install-Continue.ps1` checks the names.
- **Scripts are repeatable.** Every script can run any number of times and brings about the
  intended state.
- **One script, one job.** Shared logic lives in `scripts\lib\`, never twice.
- **The normal Claude Code stays untouched.** `claude-local` sets its variables only for its
  own process. `claude` and the VS Code extension keep using the Anthropic account.
  Unzensiert does not need Claude Code at all.
- **Every change is documented.** What was done and measured is in
  [devlog.md](devlog.md); the description concerned is updated in the same step.
- **English throughout** (since 2026-11-18): the program, what the model reads, the
  documentation. The model answers in the language the user writes in.

## Why these decisions

**Why llama.cpp directly instead of Ollama (since 2026-11-14):** Ollama also starts
`llama-server` internally but puts a layer of its own on top. Addressed directly, the options
can be set per model (above all the GPU split, which had to be the same for all models with
Ollama), and there is no second place with settings of its own any more (the Ollama app
overrode environment variables). Measurements: [model-choice.md](model-choice.md).

**Why router mode:** a single `llama-server` serves exactly one model. In router mode the
request chooses the model by its name, the server loads it when needed and unloads others
when the memory is not enough. That way switching with `/model` and the small autocomplete
model next to the large one work without any extra effort.

**Why "uncensored" depends on the model:** whether a request is refused is decided by the
model. The agent only passes text and tool calls through. So it is enough to swap the model.

**Why an own agent (since 2026-11-17):** Claude Code is a program by Anthropic built for the
cloud: its system prompt with tools comes to about 26,000 tokens at the local server, every
hook is a process of its own, and every new version can change the behaviour with local
models. Unzensiert is cut to local models (first request 2,808 tokens, guard in its own
process, help against loops) and belongs to the project; operation and tools follow Claude
Code so nothing has to be relearned. It draws its terminal itself, in the look of the
project ([style.md](style.md)). It is written in PowerShell 5.1 because that is present on
every Windows and the rest of the project is already written in it. `claude-local` stays so
the benchmark can compare both ([unzensiert.md](unzensiert.md)).

**Why Claude Code was the agent first:** the operation was identical to what was already in
use, and `llama-server` supports the Anthropic API directly.

**Why `models.json` instead of the INI file of the server:** `llama-server` reads its model
list from an INI file with absolute paths. The scripts need the same facts (context size for
the agents, file path for the benchmark). So the JSON file is the source, and
`scripts\lib\Server.ps1` generates the INI file at every start.

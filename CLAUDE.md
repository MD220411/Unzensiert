# Notes for working on this project

Local coding agent: the own agent Unzensiert (`unzensiert`, `docs\unzensiert.md`) and, for
comparison, Claude Code (`claude-local`), both with llama.cpp (`llama-server`) and local
models, with an installer and automatic updates for any Windows computer. Developed on a
computer with two graphics cards. Overview: `README.md`, structure: `docs\architecture.md`.

## Rules

- **Settings live in `config\`**, never in scripts. Scripts read them through
  `scripts\lib\Config.ps1`.
- **Project and computer kept apart.** The files in `config\` apply on every computer: no
  fixed drives, card names or card splits. What is only true for one computer (folders,
  `tensor-split`, `device`, default model) belongs in `config\machine.json`; it is not in the
  repository (`docs\setup.md`).
- **The repository is public.** No personal data in files, logs and commit messages (names,
  paths with `C:\Users\<name>`, keys); write `%USERPROFILE%` or `<installRoot>` in the
  documentation.
- **One script, one job.** Shared logic belongs in `scripts\lib\` (one topic per file), loaded
  through `scripts\_common.ps1`.
- **Scripts are repeatable** and have a header comment with purpose and usage.
- **`.ps1` files ASCII-only**, comments in them in English. Windows PowerShell 5.1 reads files
  without a BOM as ANSI.
- **Pitfalls of PowerShell 5.1** (section "The agent Unzensiert" in `docs\architecture.md`): variable names
  are case-insensitive (`$ui` is `$script:Ui`, `$agent` is a parameter `-Agent`); a list with
  one element comes back from a function as that element (`@(...)` at the call or
  `return , $list`); values of `New-Object`, `Join-Path`, `Get-Date` are PSObjects and do not
  belong in JSON for the server; `-eq`, `-ne`, `-replace` and keys of `@{}` are
  case-insensitive, use `-ceq`, `-creplace` or .NET methods for contents.
- **Everything in English** (since 2026-11-18): what the program shows (texts in
  `config\unzensiert-texts.json` and the style files), what the model reads (`config\*.md`,
  messages of guard and closing check) and the documentation in `docs\`. With every change
  update in the same step: the description of the layer (`backend.md`, `models.md`,
  `agent.md`, `unzensiert.md`), the tables of the `README.md` and an entry at the top of
  `docs\devlog.md`.
- **`docs\benchmark.md` is generated**, do not edit it by hand
  (`scripts\Benchmark-Models.ps1 -ReportOnly`).
- **After changes to `config\server.json` or `config\models.json`:**
  `scripts\Restart-Server.ps1`, then `scripts\Test-Model.ps1`.
- **After every change to `config\` or `scripts\`:** `scripts\Test-Setup.ps1`. After changes
  to `config\guard.json` or the guard also `scripts\Test-Guard.ps1`.
- **After changes to `benchmark\`:** `scripts\Test-Tasks.ps1`. Every new task gets a reference
  solution (`solution\`); the template must fail, the solution must pass.
- **After changes to `templates\` or `New-Project.ps1`:** `scripts\Test-Templates.ps1`.
- **After changes to the agent** (`scripts\unzensiert.ps1`, `scripts\lib\Agent*.ps1`,
  `scripts\lib\Update.ps1`, `config\unzensiert.json`, `config\unzensiert-prompt.md`):
  `scripts\Test-Agent.ps1`; after changes to the loop, tools or rights also
  `scripts\Test-Agent.ps1 -WithModel`. Statements about Unzensiert compared with Claude Code
  need a run of `Benchmark-Models.ps1` with both agents (`-Agent`).
- **Releases only when the user explicitly wants one**, and only with
  `scripts\New-Release.ps1`: a release installs itself on every installation with automatic
  updates. On the development computer automatic updates are off (`config\machine.json`,
  `updates`).
- **After changes to the installer** (`install.ps1`, `Install.ps1`, `Uninstall.ps1`,
  `Get-Model.ps1`, `Install-LlamaCpp.ps1`, `lib\Config.ps1`, `lib\Machine.ps1`,
  `lib\Download.ps1`, `config\setups.json`, `download` in `config\models.json`):
  `scripts\Test-Install.ps1`. Measure new tiers in `setups.json` with `Test-Model.ps1` and enter
  them in `measured`.
- **After changes to the planner** (`Plan-Models.ps1`, `lib\Planner.ps1`, `config\planner.json`):
  `scripts\Test-Install.ps1`, then on this computer `scripts\Plan-Models.ps1 -Verify` and compare
  the speed with the previous plan (`docs\planner.md`). Do not tune the split over the cards by
  hand in `machine.json`; improve the planner instead.
- **The protection serves the user's computer** (`docs\security.md`): no rules about content,
  and nothing that gets in the way of the local model's normal work in the project folder.
- **Measure instead of claiming.** Statements about speed or quality need a run of
  `Test-Model.ps1` or `Benchmark-Models.ps1`; mark unchecked assumptions as such.
- **Delete nothing outside the repository** (models, the install folder `<installRoot>`)
  unless the user explicitly asks for it.

## Checks

```
powershell -ExecutionPolicy Bypass -File scripts\Test-Setup.ps1            # configuration and scripts, without a model, a few seconds
powershell -ExecutionPolicy Bypass -File scripts\Test-Guard.ps1            # guard rules, about 25 s
powershell -ExecutionPolicy Bypass -File scripts\Test-Tasks.ps1            # benchmark tasks, without a model, about 40 s
powershell -ExecutionPolicy Bypass -File scripts\Test-Templates.ps1        # project templates, without a model, about 20 s
powershell -ExecutionPolicy Bypass -File scripts\Test-Agent.ps1            # agent Unzensiert, without a model, about 5 s (-WithModel: one task, about 30 s)
powershell -ExecutionPolicy Bypass -File scripts\Test-Install.ps1          # installer logic, without download and model, about 30 s
powershell -ExecutionPolicy Bypass -File scripts\Install.ps1 -Plan         # dry run of the installer on this computer, changes nothing
powershell -ExecutionPolicy Bypass -File scripts\Plan-Models.ps1 -Verify  # compute and check the split over the cards, 2 to 5 min
powershell -ExecutionPolicy Bypass -File scripts\Test-Model.ps1            # one profile, about 30 s
powershell -ExecutionPolicy Bypass -File scripts\Benchmark-Models.ps1      # all profiles, about 10 to 40 min
```

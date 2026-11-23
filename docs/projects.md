# Projects with the local model

How to create and work on a project so it stays maintainable even when a local model writes
most of the code.

## Creating a new project

```
powershell -ExecutionPolicy Bypass -File scripts\New-Project.ps1 -Name my-tool
powershell -ExecutionPolicy Bypass -File scripts\New-Project.ps1 -Name my-tool -Language powershell -Purpose "Cleans up log files."
```

| Parameter | Meaning |
|---|---|
| `-Name` | name of the project and its folder |
| `-Language` | `python` (default) or `powershell` |
| `-Path` | parent folder, default `projectsRoot`: `%USERPROFILE%\Projects` from `config\projects.json`, on this computer possibly from `config\machine.json` |
| `-Purpose` | one or two sentences for README and architecture |
| `-NoGit` | no repository, no first commit |

An existing folder is never touched. The new project passes its own check command right away
and has a first commit. If there is no global git identity, the new repository takes name and
address from this repository.

Then: write the purpose into the README and start `unzensiert` in the project folder.

## What the template contains

| File or folder | Purpose |
|---|---|
| `README.md` | purpose, requirements, start, check, structure, settings |
| `CLAUDE.md` | short notes for the model: commands and where things belong, with references to pattern files |
| `config\settings.json` | settings of the program; one building block reads them (`config.py` or `scripts\lib\Config.ps1`) |
| `config\check.json` | steps of the check command |
| `scripts\Check.ps1` | the one check command: syntax, tests, linter (if installed) |
| `.githooks\pre-commit` | runs the check command before every commit |
| `tests\` | a first test as a pattern |
| `docs\architecture.md` | modules and their public interfaces |
| `docs\decisions\` | one file `NNNN-title.md` per decision (situation, decision, reasons, rejected options), pattern `0000-template.md` |
| `facts\facts.json` | source of truth for facts from outside (pins, voltages, other interfaces), each with its source; section "Facts" below |
| `facts\boards\esp32.json` | board profile ESP32: existing pins, input only, flash, strapping |
| `scripts\check_facts.py` | step "Facts" of the check command |
| `CHANGELOG.md` | changes per version, scheme major.minor.patch |
| `.gitignore` | Python cache, editor files, secrets |

The templates are in `templates\project\`: `shared\` goes into every project, plus the
folder of the language. Placeholders: `{{NAME}}`, `{{PACKAGE}}`, `{{PURPOSE}}`, `{{DATE}}`; a
folder `__PACKAGE__` gets the package name.

**Adding a language:** create a folder in `templates\project\` and add its name under
`languages` in `config\projects.json`.

## The check command

```
powershell -ExecutionPolicy Bypass -File scripts\Check.ps1
```

Runs the steps from `config\check.json` one after the other and ends with exit code 1 when
one fails.

| Field of a step | Meaning |
|---|---|
| `name` | label in the output |
| `command` | command, runs in the project folder; exit code 0 means passed |
| `builtin` | instead of `command`: `powershell-syntax` checks that all `.ps1` files are readable and pure ASCII |
| `needs` | program the step needs |
| `optional` | if the program from `needs` is missing, the step is skipped instead of counted as an error |

The same command runs in three places: by hand, in the git hook before every commit and in
the closing check of `unzensiert` and `claude-local` ([agent.md](agent.md)), before the model
reports a task as done. For a project from `New-Project.ps1` it is confirmed from the start; in
other projects, and after a change of the script or its steps, you are asked before it runs
([security.md](security.md#trust-in-a-folder)).

The linter steps (`ruff`, `PSScriptAnalyzer`) are entered as optional. Neither program is
installed on the development computer; the steps are therefore untried. A search for secrets
and a check of the dependencies are still missing.

**Retrofitting an existing project:** copy `scripts\Check.ps1` from
`templates\project\shared\scripts\`, create `config\check.json` with the commands of the
project, write a short `CLAUDE.md` following the pattern of the template.

## Facts: one source of truth

Reason: during real work on an ESP32 firmware, `local-coder` made up hardware facts (pins,
voltages, configuration keys) and after changes left README, schematic and code
contradicting each other. The benchmark catches neither; a cross-check with a large model
found both.

So every project has `facts\facts.json`: every fact from outside exactly once, with its
source or marked as an assumption. `scripts\check_facts.py` runs in the check command (so also
in the git hook and in the closing check) and reports as errors:

| Check | Example message |
|---|---|
| fact without a source (except `"status": "assumption"`, which only warns) | `fact 'uart0.tx' has no 'source'` |
| name in the code with another value (`#define`, assignment in C, Python, PowerShell, key in JSON/YAML/INI) | `main/ir/ir.h:21 sets IR_LED_PIN = 14, facts say GPIO15` |
| pin in the documentation with the wrong signal (`GPIO18 (SID`, `SID = GPIO18`) | `README.md:47 gives SID as GPIO18, facts say GPIO17` |
| pin in documentation or code that is not in the facts | `GPIO31 is mentioned in README.md ... (and esp32 has no GPIO31)` |
| a pin given out twice (per device) | `GPIO15 on device 'controller' is given to several facts` |
| against the board profile: pin missing, output on an input pin, flash pin | `GPIO39 is input-only on esp32 but is used as 'out'` |

Numbers are compared as numbers (`0x76` equals `118`, `3.3` equals `3.3V`), pins in every
spelling (`GPIO4`, `GPIO_NUM_4`, `4`). Strapping pins and assumptions appear as warnings.
Format of the file: `facts\README.md` in the project. The German status words of earlier
versions (`belegt`, `annahme`) are still understood.

Tried on a copy of the ESP32 project `HackMD` with 25 facts for two devices: passed without
errors once five free pins mentioned in the documentation were under `allow_unlisted_pins`;
all eight deliberately built-in errors (wrong pin in README and header, wrong buffer size in
the second firmware, flash pin, output on an input pin, pin that does not exist, fact without
source, pin not recorded) were found.

The rule for it is in the `CLAUDE.md` of the template and for all projects in
`config\coding-rules.md` (section "Check facts instead of guessing").

**Retrofitting an existing project:** copy `facts\` and `scripts\check_facts.py` from
`templates\project\shared\`, enter the facts, add the step `python -B scripts\check_facts.py`
to the check command of the project.

## Working in a project

- **Fixed workflows:** `/feature <description>`, `/bugfix <error>`, `/review` (in
  `claude-local` with the prefix `/local:`, [agent.md](agent.md)).
- **Small steps:** one task per session, then `/clear`. One commit per finished change. Break
  large plans into a list in `docs\` first, then hand them out point by point. A task that
  needs many files at once does not succeed every time even with 128k context (measured:
  task `longcontext`, 3 of 6).
- **Interfaces:** what other modules may use is in the table in `docs\architecture.md`. When
  an interface, a file format or a dependency changes, a file belongs in `docs\decisions\` and
  an entry in `CHANGELOG.md`.

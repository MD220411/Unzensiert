# Extending

Where to start when you want to change the project. All commands run from the project folder,
scripts each with `powershell -ExecutionPolicy Bypass -File scripts\<name>`.

## Signposts

| Plan | Where | Description |
|---|---|---|
| Add a new model (with a `download` entry) | `config\models.json` | [models.md](models.md) |
| Recompute the split over cards and main memory | `scripts\Plan-Models.ps1 -Verify` | [planner.md](planner.md) |
| Change reserves, context sizes or tolerance of the planner | `config\planner.json` (per computer: `planner` in `machine.json`) | [planner.md](planner.md) |
| Set context or GPU split by hand for this computer only | `config\machine.json` (the planner overwrites it at its next run) | [setup.md](setup.md) |
| Change which model the installer suggests for how much graphics memory | `config\setups.json`, measured with `Test-Model.ps1` | [setup.md](setup.md) |
| Change the installer | `scripts\Install.ps1`, `lib\Machine.ps1`, `lib\Download.ps1`, then `Test-Install.ps1` | [setup.md](setup.md) |
| Change the default model, short names or the choice of `/model` | `config\agent.json` | [agent.md](agent.md) |
| Change the working rules of the local model | `config\coding-rules.md` | [agent.md](agent.md) |
| Change or switch off the closing check | `stopCheck` in `config\agent.json`, text in `config\closing-check.md` | [agent.md](agent.md) |
| Change (reviewer, threshold) or switch off the second look | `review` in `config\agent.json`, review instructions in `config\second-look.md` | [agent.md](agent.md) |
| Add a workflow | file in `config\workflows\commands\` | [agent.md](agent.md) |
| Change the project template, add a language | `templates\project\`, `config\projects.json` | [projects.md](projects.md) |
| Update llama.cpp, change the port | `config\server.json` | [backend.md](backend.md) |
| Change guard rules (what is blocked, when it asks) | `config\guard.json`, cases in `tests\guard-cases.json` | [security.md](security.md) |
| Change texts, colours or glyphs of the terminal | `config\unzensiert-texts.json`, `config\styles\` | [style.md](style.md) |
| Compare models or settings | `config\benchmark.json` | below |
| Connect another agent | a new starter | [agent.md](agent.md) |

## Comparing models and settings

`scripts\Benchmark-Models.ps1` measures every profile from `config\benchmark.json`: load
time, speed, MTP hit rate, tool calls, GPU memory and the agent tasks that an agent solves and
a hidden check grades. The check also records which working rules the agent followed.

- **Which agent:** `agent` in `config\benchmark.json` (`unzensiert`), for one run
  `-Agent unzensiert` or `-Agent claude-local`. Both get the same arguments, the same allowed
  commands (`allowedTools`) and the same set of tools; every agent has its own record (field
  `client`), runs under the same label stand side by side in the report. Records from before
  2026-11-17 count as `claude-local`.
Result: `docs\benchmark.md`, raw data: `logs\benchmark\results.jsonl`.

- **Adding a new model:** create a profile ([models.md](models.md)), enter its name under
  `models` in `config\benchmark.json`, start the script. Profiles already measured are
  skipped.
- **Comparing a setting** (context, GPU split, thinking effort, MTP length): either create a
  second profile with the other value and measure both, or change the value in the profile,
  run `Restart-Server.ps1` and measure with `-Label <name>`. The label separates the runs in
  the report.
- **Measuring only a part:** `-Only "local-c*"` chooses profiles, `-Tasks planner` or
  `-Tasks bugfix,feature` chooses tasks. Only raw values without agents: `-SkipAgent`.
- **Like a project made from the template:** `-Overlay project` lays over every task what a
  project from `New-Project.ps1` has: a short `CLAUDE.md`, `config\check.json` and the check
  command `scripts\Check.ps1` (files in `benchmark\overlays\project\`, shared files in
  `overlay.json`). That way you can measure what project notes and check command achieve.
  `Test-Tasks.ps1 -Overlay project` checks that the tasks are sound with it.
- **With a workflow:** `-Prefix /local:feature` puts the text in front of every task (for
  Unzensiert also `/feature`).
- **With the second look:** `-Git` makes every working folder a git repository with the task
  files as the first commit. Only then does the closing check see a diff, and the second look
  ([agent.md](agent.md)) runs as well. Without `-Git` the benchmark measures everything except
  the second look. `-ReviewModel local-coder` chooses another reviewer for this run (through
  the environment variable `CLAUDE_LOCAL_REVIEW_MODEL`, which the agent passes on to the
  closing check), `-ExtraSeconds 300` extends every time limit by the duration of the review.
  Every run records the reviews from `review.log` (finding, duration) in its result.
- **Sleep:** while the script runs, it keeps the computer from going to sleep
  (`SetThreadExecutionState`, not a system setting; the request ends with the script). Before
  that the computer went to sleep during long measurements.
- **When the agent does not start** (no result line, for example because another session is
  rebuilding a script or `config\` right now), the script stops with exit code 1. The runs
  before stay in the record, the reason is in the field `error`. Then measure the missing
  tasks with `-Tasks` under a new `-Label`. Do not change anything in `config\` and
  `scripts\` during a measurement: every run reads both anew.
- **Checking reliability:** `-Repeat 3` solves every task three times. Because models are
  random, a single run is only an indication; the same task with the same model has taken
  anywhere between 122 s and 412 s.
- **During the measurement** do not use VS Code with Continue: the autocomplete model would
  load and distort the values.

All nine tasks three times take about an hour and a half per profile; the five harder ones
alone about an hour.

Settings in `config\benchmark.json`:

| Field | Meaning |
|---|---|
| `tasks`, `models` | what is measured |
| `agentTimeoutSeconds` | time limit per run (600 s) |
| `taskTimeoutSeconds` | different time limit for single tasks |
| `allowedTools` | commands the agent may run without a question (nobody sits at the terminal in the benchmark; everything else counts as refused) |
| `workDir` | working folder, outside the repository |

### Existing tasks

| Task | Content | Difficulty | Rules checked |
|---|---|---|---|
| `bugfix` | find and fix a bug | easy | none |
| `feature` | add a function | easy | none |
| `multifile` | change across several files | easy | none |
| `planner` | room planner after `SPEC.md`: fix bugs in two modules, add a module and a command of the command line; the check tests edge cases the included tests do not cover | medium | none |
| `extend` | extend an existing project to several warehouses; old tests, old calls and old data files must keep working | medium | 5 |
| `refactor` | refactoring across seven files: all file access into a new module, write atomically; the check also reads the structure of the code | medium | 4 |
| `psscript` | extend a PowerShell script with filters, JSON output and tolerant reading; must run with Windows PowerShell 5.1 | hard | 5 |
| `screenshot` | fix a bug from a screenshot; what goes wrong is only in the picture | easy to medium | 4 |
| `longcontext` | apply 15 rule changes from a list to 20 differently written country modules and add a country; fills a context of 64k | hard | 4 |
| `datenblatt` (datasheet) | driver for the made-up sensor HX-7 after the enclosed datasheet; its predecessor HX-5 lies next to it and differs in address, byte order, formula and procedure. Measures faithfulness to facts: whoever copies from the HX-5 or guesses fails. The material is in German | medium | 5 |
| `pinwechsel` (pin change) | move the pump from GPIO17 to GPIO23, add a rain sensor on GPIO17. The pins appear in five places (configuration, fallback value in the code, README, wiring plan with the header pin, `facts.json`), plus the tests. Measures consistency across files; the project has a check command and fact comparison like one from `New-Project.ps1`. The material is in German | medium | 5 |

The three easy tasks are passed by all good models; they only differ in time. The assessment
of the results is in [model-choice.md](model-choice.md).

The ids `datenblatt` and `pinwechsel` and their German material stay as they are, so the
results stay comparable with earlier runs; they also show that the agent copes with material
that is not in English.

### Measuring working rules

The prompts of the five newer tasks only ask for the result. That the README is updated, a
test written or a setting put into the configuration file is asked for only by
`config\coding-rules.md`. Whether it happens is measured by the check with the building blocks
from `benchmark\lib\rulecheck.py` and printed as a line `RULES {"readme": true, ...}`.
Passing or failing does not depend on it.

| Rule | Counts as followed when |
|---|---|
| `readme` | the README was changed and names the new feature |
| `tests` | a new or changed test file names the new feature |
| `config` | the new value (name of the default warehouse, number of sources) is a new entry in the configuration file |
| `docstrings` | every new public function, class and every new module has a description |
| `headers` | every new PowerShell script begins with a comment |
| `nodeadcode` | no new line contains commented-out code (in Python only comments that compile as Python; worked examples like `# raw = 512 -> 2.0` do not count) |
| `fakten` (facts) | `facts/facts.json` has a new fact about the new feature, with its source |

These are approximations that can be checked mechanically. They tell whether something
happened, not how well. The report shows the rate per run, per task and per rule.

### A new task

Folder `benchmark\tasks\<name>\` with

- `files\`: starting files, copied into a working folder,
- `prompt.txt`: the task for the agent,
- `check.py`: gets the working folder as argument, exit code 0 means passed; optionally it
  prints the line `RULES {...}` (pattern: `benchmark\tasks\extend\check.py`),
- `solution\`: reference solution, only the files that change compared with `files\`. The
  agent never sees it.

Enter the name in `config\benchmark.json` under `tasks`, then run `scripts\Test-Tasks.ps1`:
the check must fail on the unchanged template and pass on the reference solution, with all
rules followed. If a task brings tools of the project template along
(`scripts\check_facts.py`, `scripts\Check.ps1`, like `pinwechsel`), `Test-Tasks.ps1` also
checks that it is the current version; after a change to the template renew the copy. While
the tasks were built this self-test found two errors in the checks before any model ran, and
the measurement found a third (development log of 2026-11-15).

Two tasks have generated files:

- `longcontext`: `python benchmark\tasks\longcontext\generate.py` writes `files\`,
  `solution\`, `probe.py` and `expected.json` from a table in the script. Changes to the task
  belong in the table, not in the generated files.
- `screenshot`: `benchmark\tasks\screenshot\Make-Image.ps1` draws `files\error.png`.

## New scripts

- A script has one job. The header comment says what it does and how to call it.
- At the start `. "$PSScriptRoot\_common.ps1"`. That loads the building blocks from
  `scripts\lib\`:

  | File | Functions |
  |---|---|
  | `lib\Config.ps1` | `Get-ServerConfig`, `Get-AgentConfig`, `Get-ModelsConfig`, `Get-ModelNames`, `Get-ModelProfile`, `Get-ModelContextSize`, `Resolve-ModelName`, `Read-JsonFile` |
  | `lib\Server.ps1` | `Start-Server`, `Stop-Server`, `Test-ServerUp`, `Invoke-ServerApi`, `Get-ServerModels`, `Wait-ModelLoaded`, `Stop-AllModels` |
  | `lib\Measure.ps1` | `Measure-Generation`, `Measure-PromptSpeed`, `Test-ToolCall`, `Get-GpuMemory` |
  | `lib\Tasks.ps1` | `New-TaskWorkCopy`, `Invoke-TaskCheck`, `Get-TaskOverlayDir` |
  | `lib\Quality.ps1` | `Get-QualitySettings`, `Get-PluginDir`, `Merge-Settings`, `Invoke-StopHook` |
  | `lib\Review.ps1` | `Invoke-Review`, `Get-ChangeForReview`, `New-ReviewRequest`, `ConvertFrom-ReviewAnswer`, `Get-LastUserPrompt`, `Invoke-Git` |
  | `lib\Projects.ps1` | `Get-ProjectsConfig`, `New-ProjectFromTemplate`, `Invoke-ProjectCheck`, `Initialize-ProjectRepository` |

- Values (paths, ports, model names) come from `config\`, never from the script.
- Logic that can be shared belongs in `scripts\lib\`, in the file with the fitting topic. A
  new topic gets a new file, which is loaded in `_common.ps1`.
- Only ASCII characters in `.ps1` files. Windows PowerShell 5.1 reads files without a BOM as
  ANSI and destroys non-ASCII letters.
- Scripts must be repeatable: a second run changes nothing more.

## Keeping the documentation up to date

- The documentation is in English.
- Every change gets an entry at the top of [devlog.md](devlog.md): what was done, what was
  measured, what is open.
- The description of the layer concerned (`backend.md`, `models.md`, `agent.md`,
  `unzensiert.md`) and the tables in the `README.md` are updated in the same step.
- `docs\benchmark.md` is generated and not edited by hand. The assessment of the numbers is in
  [model-choice.md](model-choice.md).

## A cloud model as a fallback

`claude-local` takes the address from `config\server.json`. For a service with an
Anthropic-compatible API and a key, create a starter of your own after the pattern of
`scripts\claude-local.ps1` that sets `ANTHROPIC_AUTH_TOKEN` from an environment variable. Keys
do not belong in the files of this folder.

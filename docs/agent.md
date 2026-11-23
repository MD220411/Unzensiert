# Agent: Claude Code through `claude-local`

Since 2026-11-17 the default agent of the project is **Unzensiert** (`unzensiert`, its own
program, [unzensiert.md](unzensiert.md)). `claude-local` stays for comparison: it starts the
normal Claude Code but connects it to the local server instead of the Anthropic cloud. The
starter is `scripts\claude-local.ps1`; `bin\claude-local.cmd` makes it available in every
terminal.

Both agents share `config\agent.json` (model, short names, choice, working rules, closing
check, second look, workflows, tools, `onExit`), the guard and the look. So what this document
says about these parts also applies to Unzensiert; only the start, the variables of Claude
Code and the limits at the end concern `claude-local` alone.

## Using it

| Command | Effect |
|---|---|
| `claude-local` | Session with the default model (`model` in `config\agent.json`, on this computer possibly from `config\machine.json`). If it is not downloaded, the first downloaded model from `picker` starts. |
| `claude-local -Model fast` | Session with a short name from `aliases` or a profile name from `config\models.json`. If the model is not downloaded, `claude-local` names the command to download it. |
| `/model` in the session | Switch the model without ending the session. The choice shows the entries under `picker` whose model is downloaded on this computer. |
| `claude-local -p "question"` | a single answer without a session |
| `claude-local --continue` | continue the last session in the folder |
| `claude-local -OnExit keep` | keep the models loaded after this session (overrides `onExit`) |

All further arguments go to Claude Code unchanged.

## Settings (`config\agent.json`)

| Key | Value | Purpose |
|---|---|---|
| `model` | `local-coder` | Default model. The installer writes the model that fits the graphics memory into `machine.json` ([setup.md](setup.md)). |
| `aliases` | `unzensiert` → `local-coder`, `fast` → `local-fast`, `qwen38` → `local-qwen38` | Short names for `-Model` |
| `picker` | list of `model`, `label`, `description` | Entries of the choice of `/model` |
| `rulesFile` | `coding-rules.md` | File in `config\` that is appended to the system prompt. Leave it empty or remove it to start without rules. |
| `stopCheck` | `enabled`, `commands`, `timeoutSeconds`, `maxBlocks`, `reminderFile` | Closing check, see below. `enabled: false` switches it off. |
| `pluginDir` | `workflows` | Folder in `config\` with the workflows `/feature`, `/bugfix`, `/review` (in `claude-local` `/local:feature` ...). Leave it empty or remove it to start without them. |
| `tools` | `Bash,Read,Edit,Write,Glob,Grep` | Tools the model may use (with Claude Code `--tools`). Leave empty or remove for the full set of Claude Code; Unzensiert only knows `Bash`, `PowerShell`, `Read`, `Edit`, `Write`, `Glob`, `Grep` (plus its own `EditLines` when switched on, [unzensiert.md](unzensiert.md#tools)). Without Git for Windows both replace `Bash` by `PowerShell`, see "Lean tool set". |
| `env` | auto memory and bundled skills off | Switches of Claude Code, set for this process only |
| `onExit` | `unload` | What happens when the last session ends: `unload` unloads the models of the agent, `stop` stops the server, `keep` leaves everything loaded. See below. |
| `gitCheck` | `true` | Note at start when the folder is not a git repository or has uncommitted changes ([security.md](security.md)) |
| `contextSafetyFactor` | `0.9` | Claude Code is told 90 % of `ctx-size` as its window, because it only estimates the token count |
| `fallbackContextTokens` | `32768` | Assumption for profiles without `ctx-size` |
| `maxOutputTokens` | `16384` | Limit for one answer |

The address of the server is not here but in `config\server.json`.

## Working rules for the local model

`config\coding-rules.md` is appended to the system prompt in every session (Claude Code:
`--append-system-prompt-file`). The rules point the model at building software so that it
stays maintainable: structure first, then code; one module per job; settings in configuration
files; README, file header and docstrings; tests before finishing; documentation in the same
step as the change.

- **Changing the rules:** edit the file. Applies from the next session, no restart of the
  server needed.
- **Keep it short.** The file counts towards the context in every request (measured 544 tokens
  before the section on PowerShell, now estimated at 750).
- **Precedence:** a `CLAUDE.md` or `AGENTS.md` in the project folder and explicit instructions
  in the session take precedence. Project-specific things (language, structure, commands for
  testing) belong in the `CLAUDE.md` of the project, not in the general rules.

The section "PowerShell scripts" of the rules names the peculiarities of Windows PowerShell
5.1 on which the models failed in the benchmark (stderr and exit code, unwanted output, lists
with one entry).

The section "Check facts instead of guessing" answers two classes of errors from real work on
an ESP32 firmware: made-up facts (pins, voltages, configuration keys) and values that drifted
apart in README, schematic and code after a change. In the project a program checks that
([projects.md](projects.md), section "Facts"); whether the rule alone achieves anything is not
measured.

A local 27B model follows such rules less reliably than Claude: measured, the README entry and
the test came about without being asked in less than half of the runs. That is why the
closing check asks about them once more at the end of every answer with changes.

The rules were German until 2026-11-18 and are English since then.

## Closing check

When the model wants to end an answer in which it changed files, the closing check runs
(Unzensiert in its own process, `claude-local` through `scripts\hooks\Check-Stop.ps1` as a
`Stop` hook of Claude Code):

1. **Check command of the project.** If the project folder has `scripts\Check.ps1` or
   `Check.ps1` (`commands`), it is run, once you confirmed it: Unzensiert asks before the first run,
   `claude-local` at its start, and a change of the script or its steps asks again
   ([security.md](security.md#trust-in-a-folder)). If it fails, the model gets the end of the output
   back and keeps working, at most `maxBlocks` times (3) in a row. After that it may stop, and
   a note appears in the terminal to look for yourself.
2. **Reminder.** Once per answer the model gets the text from `config\closing-check.md`: the
   task read once more and checked requirement by requirement against the change, special
   cases included; test written and run, README updated, fixed values in the configuration
   file, cleaned up. If something is missing, it makes up for it. A point is left out when the
   files changed in this answer show that it is done (`reminderPoints`: a test file, a README
   or file in `docs`, a configuration file). No file settles the point on the task, so
   whenever program code was changed the reminder comes; after changes to documentation only,
   no reminder comes.

After answers without file changes nothing happens. Whether files were changed, the hook reads
from the history of the session (calls of `Edit` and `Write`); changes made only through shell
commands are not seen. It only counts real calls (`tool_use` blocks, every call id once):
Claude Code also writes the tool descriptions into the history and repeats earlier messages
with every request. An error in the hook itself always lets the model stop. The state per
session is in `<installRoot>\run\stop\`; the hook gets the folder through the variable
`CLAUDE_LOCAL_ROOT` (`scripts\hooks\HookEnvironment.ps1`).

Measured on 15 runs of `local-coder`: with the closing
check the README names the new feature in 15 instead of 7 runs, a test exists in 15 instead
of 6. The price is time: with the first version, which always reminded, the runs took 50 %
longer altogether, because every answer with changes needs at least one more round of the
model. The reminder alone does not bring the value into the configuration file (0 of 6); the
`CLAUDE.md` of the project does that (5 of 6).

The point on the task (since 2026-11-18) was measured on eight benchmark runs that had failed
because the model overlooked a requirement: continued with it, the model fixed five of them;
continued with the reminder without that point, none. In a full run over the eleven tasks 10
instead of 9 passed, and the tasks took about a fifth longer altogether (one run per task).

- **Changing the text:** edit `config\closing-check.md`. Points have the form `- [name] text`;
  which files settle a point is under `reminderPoints` in `config\agent.json`
  (`doneWhenEdited`: pattern for the path; `codeOnly`: the point only counts when program code
  was changed).
- **Always the whole text:** remove `reminderPoints`.
- **Only the check command, no reminder:** set `reminderFile` to `""`.
- **Switching it off:** `enabled` to `false`.
- **Troubleshooting:** set the environment variable `CLAUDE_LOCAL_HOOK_DEBUG=1`; the hook then
  writes to stderr why it gave up.

Every project from `New-Project.ps1` comes with a check command; an existing project can be
retrofitted ([projects.md](projects.md)).

## Second look

After a larger change a second local model checks in a fresh context whether it is right. It
is the third step of the closing check and runs once per answer, as soon as check command and
reminder have nothing open any more, and only in a git repository:

1. `scripts\Invoke-Review.ps1` collects the uncommitted change (diff against `HEAD` and new
   files) and counts the changed lines. Below `minChangedLines` (20) it ends here.
2. The reviewer (`local-qwen38`; if it is not downloaded on this computer, the default model
   itself in a fresh context) gets in one single request: the review instructions
   `config\second-look.md`, the last input of the user as the task, the `CLAUDE.md` and
   `facts\facts.json` of the project, the diff and the changed files in full, the smallest
   first, as far as they fit into `maxFileChars`. It needs whole files because a
   contradiction is often in an unchanged line, for example when the README further down
   still names the old pin. It has no tools and runs nothing.
3. It answers with lines `ERROR | file:line | ...` and `HINT | ...` or with `NO FINDINGS`.
   (The German words of earlier versions, `FEHLER` and `HINWEIS`, are still understood.)
4. With at least one `ERROR` the author gets the list back, with the task to check every
   finding against the code, fix what is right and explain to the user what is not. Only
   `HINT` lines are shown to the user in the terminal; the author does not keep working. If
   the reviewer does not run because server, model or time are missing, a note appears and
   the model may stop.

The router loads the reviewer and unloads `local-coder` for it. Afterwards it loads
`local-coder` again and reads the conversation in anew. Every run is a JSON line in
`<installRoot>\logs\review.log` (project, lines, seconds, number of errors and hints).

By hand, also with another model as reviewer:

```
powershell -ExecutionPolicy Bypass -File scripts\Invoke-Review.ps1 -Folder D:\Projects\my-tool -Task "what the change is meant to do"
powershell -ExecutionPolicy Bypass -File scripts\Invoke-Review.ps1 -Folder D:\Projects\my-tool -Model local-coder
```

| Key under `review` | Value | Purpose |
|---|---|---|
| `enabled` | `true` | second look on or off |
| `model` | `local-qwen38` | profile or alias of the reviewer |
| `minChangedLines` | 20 | it does not review smaller changes (assumption: below that, waiting and reloading are not worth it) |
| `maxDiffChars`, `maxFileChars` | 60000, 80000 | limits for diff and whole files in the request |
| `maxTokens` | 8192 | limit of the answer including thinking |
| `timeoutSeconds` | 600 | including loading the reviewer; the time limit of the hook grows by this value |
| `instructionsFile` | `second-look.md` | review instructions in `config\` |

**Measured** on a copy of the ESP32 project `HackMD`, on a change of 20 lines: IR LED moved to
another pin and `ir_send_repeat` added, with built-in errors. One request per run:

| Built-in error | `local-qwen38` (3 runs) | `local-coder` as reviewer (2 runs) |
|---|---|---|
| loop sends once too often (`i <= count`) | 3 / 3 | 2 / 2 |
| README further down still names the old pin | 3 / 3 | 2 / 2 |
| header comments in `ir.h` and `ir.c` name the old pin | 3 / 3 | 2 / 2 |
| `vTaskDelay(gap_ms)`: milliseconds instead of ticks | 0 / 3 | 2 / 2 (once as a hint) |
| made-up statement "GPIO26 is 5V tolerant" | 0 / 3 | 1 / 2 (as a hint) |
| duration, with loading | 33 to 87 s | 76 to 128 s |

The same change without errors: no finding in two runs each of both reviewers, so no false
alarm. End to end through the closing check, called the way Claude Code does it: reminder,
then second look (53 s), finding to the author, then the end. Limits: a single case, few runs.
Here `local-coder` as reviewer found more, `local-qwen38` was faster. The user chose
`local-qwen38` (variant A).

**In the benchmark** (so far only the tasks `extend`, `refactor` and `psscript`, three times
each): 9 reviews, 126 s on average. One ERROR finding, and it was real (a test without `test_`
that never ran); no false alarm; one failed run went unnoticed. The three tasks took 53 %
longer altogether than without the second look. A measurement with `local-coder` as reviewer
is still open.

- **Another reviewer:** change `model`, for example to `local-coder`. For a single run it also
  works through the environment variable `CLAUDE_LOCAL_REVIEW_MODEL`.
- **Switching it off:** `enabled` to `false`.

## Workflows

| Command | Procedure |
|---|---|
| `/feature <what to build>` | read, acceptance criteria, plan, tests, code, check, documentation, report |
| `/bugfix <error, message or image file>` | reproduce, cause, first a test that shows the bug, then the fix, check, report |
| `/review [what]` | review the latest changes with fresh eyes without changing anything; best in a new session |

The workflows are a plugin in `config\workflows\` (`commands\*.md`, one command per file).
Unzensiert reads them directly (`/feature`, also `/local:feature`). For `claude-local` they are
loaded with `--plugin-dir` for that launch only, and the normal `claude` does not get them;
there the prefix `local:` is needed, the name of the plugin (`/local:feature`). Checked is the
call with `claude-local -p "/local:bugfix ..."`; `/bugfix` without prefix is not recognised
there. Whether the interactive session of Claude Code suggests the commands while typing `/`
is not checked. (Until 2026-11-18 the plugin was called `lokal` and the review `/pruefen`.)

Only `/feature` is measured, on one task: `extend` three times, 2 passed, all 15 rules
followed, also the value in the configuration file (0 of 3 without the workflow).

A new workflow is a new file in `config\workflows\commands\` with `description` in its header;
`$ARGUMENTS` stands for the text after the command.

## GPU memory after the session

When a session ends (`exit`, `/exit`, Ctrl+D, also a run with `-p`), `claude-local` cleans up
and reports the result in one line, for example
`claude-local: models unloaded, GPU memory used now (MiB): RTX 5070 Ti 7, RTX 3060 0`.

- **`unload` (default):** the starting model and the models from `picker` are unloaded. The
  server keeps running and takes no GPU memory; Continue can keep using it, the autocomplete
  model stays loaded.
- **`stop`:** the server is stopped, and with it the autocomplete model.
- **`keep`:** nothing happens. Useful when many short runs follow each other; that is why the
  benchmark calls the agents with `-OnExit keep`.

If another session of `claude-local` or `unzensiert` is still running, the models stay loaded,
and only the last one cleans up. Every session leaves a mark in `<installRoot>\run\sessions\`
for that (`scripts\lib\Session.ps1`); marks of ended processes are ignored and deleted.

If the terminal window is closed, `claude-local` cannot clean up. Then the model frees its
memory itself after 30 minutes without a request (`sleep-idle-seconds`,
[backend.md](backend.md)).

## Protection

Before every tool call of the model a guard runs that blocks destructive commands and asks
about delicate ones; normal work in the project folder stays free. If the model says a command
was blocked by the "guard of claude-local", the reason is in the message and in
`<installRoot>\logs\guard.log`. Rules, limits and how to change them:
[security.md](security.md).

## Images

The models of the agent read images: paste with Alt+V, drag a file into the terminal or name
its path ("look at `error.png`"). Requirements and measurements: [models.md](models.md),
section "Images".

## Lean tool set

Claude Code brings many tools (subagents, skills, notes, web, task lists). Each one appears
with its description in the prompt. For a local model that is ballast: the prompt gets longer,
and weaker models call the extras without reason. `claude-local` therefore only allows the six
tools needed for programming and switches off auto memory and the bundled skills.

Measured with `local-coder`, nine runs: 375 s with the lean set, 431 s with the full one, both
9 of 9. The difference is within the usual spread.

Whoever needs subagents, web search or skills adds their names to `tools` (for example
`Agent`, `WebFetch`, `WebSearch`, `Skill`) or removes the key.

**Without Git for Windows.** The tool `Bash` needs Git Bash. If `claude-local` does not find it
(`lib\Machine.ps1`, `Find-GitBash`), it replaces `Bash` by `PowerShell` and sets
`CLAUDE_CODE_USE_POWERSHELL_TOOL=1`. Benchmark and working rules are only measured with
`Bash`; the agent is untested with `PowerShell`. The installer offers Git for Windows.

## What `claude-local` sets

Only for its own process; the normal `claude` stays unchanged:

| Variable or argument | Purpose |
|---|---|
| `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY=` | Connection to the local server. The token is the key of the server ([security.md](security.md)); if none is required, it says `local`, because Claude Code needs a value. |
| the same file with `hooks` | Guard: checks every tool call of the model before it runs ([security.md](security.md)). |
| `ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_OPUS/SONNET/HAIKU_MODEL` | All built-in model names point to the starting model, also the small model for background requests. |
| `CLAUDE_CODE_SUBAGENT_MODEL` (removed) | Subagents get no fixed model and so follow the main model after a switch with `/model`. |
| `--settings <file>` with `modelPicker` | The choice of `/model` shows the entries from `picker` instead of the Anthropic models. The file (`%TEMP%\claude-local-settings.json`) applies to this launch only. |
| the same file with `theme` and `statusLine`, plus `CLAUDE_LOCAL_LOOK=<mood>` | Look of the local session: colour theme of the local mood of the active style ("Free" in Breakout, "Ember" in Night Shift) and a status line with the memory of both graphics cards. Only if the look is installed ([style.md](style.md)). |
| `CLAUDE_CODE_MAX_CONTEXT_TOKENS` | The real context window. Without the value Claude Code assumes a much larger window and never compacts in time. The value applies to the whole session; with several models in the choice the smallest window counts. |
| `CLAUDE_CODE_MAX_OUTPUT_TOKENS` | Limit the answer length |
| `--append-system-prompt-file <file>` | Working rules, see above |
| `--settings <file>` with `hooks.Stop` | Closing check, see above |
| `--plugin-dir <folder>` | Workflows `/local:feature`, `/local:bugfix`, `/local:review`, see above |
| `--tools <list>` | Lean tool set from `tools`, see above; without Git Bash with `PowerShell` instead of `Bash` and `CLAUDE_CODE_USE_POWERSHELL_TOOL=1` |
| `CLAUDE_LOCAL_ROOT`, `CLAUDE_LOCAL_PROJECTS` | Install and project folder of this computer for the hooks (guard, closing check), set by `scripts\_common.ps1` |
| `CLAUDE_CODE_DISABLE_AUTO_MEMORY`, `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS` | From `env`: no notes in the memory folder, no bundled skills |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | No telemetry and update checks in local mode |

## Known limits

- **Background requests after a model switch.** The small model for side tasks stays the
  starting model. If Claude Code sends such requests after a switch with `/model`, the server
  loads the starting model again and unloads the chosen one. None came up in runs with `-p`;
  it is not measured for interactive sessions.
- **The choice of `/model`** is only checked through the start with `-p` and the generated
  settings file, not in an interactive session.
- **The warning `claude.ai connectors are disabled`** and the line
  `[claude-code:unrecognized_model]` are expected in local mode and have no effect.
- **Context.** Even 128k fill up; Claude Code then compacts. For a new task, better a new
  session or `/clear`.

## Connecting another agent

Every tool that accepts an OpenAI-compatible address (Roo Code, Cline, OpenCode) can use
`http://127.0.0.1:8080/v1` with a profile name as the model. A starter of your own follows the
pattern of `scripts\claude-local.ps1` and `bin\claude-local.cmd`.

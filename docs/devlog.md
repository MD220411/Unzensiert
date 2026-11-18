# Development log

New entries go at the top. Measurements from `scripts\Test-Model.ps1` are also in
`logs\model-tests.log`. The entries up to 2026-11-18 midday were written in German and
translated; names of runs, task ids and file names of the time are kept as they were (what
they are called today is noted where it helps).

## 2026-11-18 evening: umlauts in the output of commands

Found in the sessions of `vergleich2` and `schleife1`: 13 tool results contained `�` instead of
an umlaut, all German error messages of a `powershell.exe` the model had started through the
Bash tool (`F�r "TryParseExact" und die folgende ...`). Unzensiert read the output of a command
as UTF-8; a `powershell.exe` started from Git Bash writes in the code page of the console (850,
`ü` is the byte 0x81). Under the PowerShell tool this does not happen, its prefix sets the
console to UTF-8 (checked: `46 C3 BC 72`).

### Done

- `scripts\lib\AgentTools.ps1`: `Invoke-ToolShell` takes the bytes of standard output and error
  (`BaseStream.CopyToAsync`), the new `ConvertFrom-OutputBytes` decodes them: a byte order mark
  decides first (as the StreamReader did before), otherwise UTF-8, and only if that fails line by
  line, each line that is not valid UTF-8 in the OEM code page.
- `scripts\hooks\Check-Stop.ps1`: the reason of the closing check began with the German
  "Abschlusspruefung von"; now "Closing check of" (the last German text the model read; the run
  `english1` still had it).

### Checked

- `Test-Agent.ps1` with five new cases (UTF-8 stays, a code page line, mixed lines, byte order
  mark of UTF-8 and UTF-16) and the real case: `printf` with UTF-8 plus `powershell.exe` with
  `ü` from Git Bash, both readable. Before the change the same command gave `F�r`.
- `Test-Agent.ps1 -WithModel` and `Test-Setup.ps1` pass.

## 2026-11-18 afternoon: disclaimer

The user's wish: a disclaimer on GitHub in case people use the program for illegal things.

- New `DISCLAIMER.md`: free, non-commercial hobby project; lawful use only, within the
  licences of the models; the user alone is responsible for requests, output, commands run and
  their consequences; the author operates no service and has no control over the use; the
  models are uncensored and their output is unchecked; llama.cpp and the models come from
  third parties; no warranty and no liability as far as the law allows (MIT License); the guard
  is no sandbox.
- `README.md`: a line under the links at the top and a section "Disclaimer" before "License",
  both pointing to `DISCLAIMER.md`.

Not legal advice: a disclaimer does not exclude every liability (in Germany, for example, not
for intent and gross negligence).

## 2026-11-18 afternoon: where the time goes, speculative decoding measured

The user's wish: look for further improvements of any kind, as long as the result gets better
for the user. First question: where does the time of a task go?

### Measured

- **Time:** from the server log of `vergleich2`, the model's time was 97 % of the task time of
  Unzensiert (92 % for Claude Code); of that, 86 % writing and 14 % reading the prompt. Tools,
  the guard and the agent itself hardly count; `unzensiert` itself starts in 0.5 s (bare
  PowerShell 0.13 s). The guard denied or asked nothing in the 33 runs of Unzensiert.
- **Output of the model** (33 sessions, characters): 27 % thinking, 8 % text, 65 % tool
  arguments. 41 % repeats a passage of at least 32 characters from earlier in the conversation
  (`old_string` 88 %); 62 full rewrites of existing files with Write.
- **Speculative decoding**, replay of 33 points of the sessions against a separate
  `llama-server` (port 8099) with the settings of `local-coder`: MTP with 4 tokens (today)
  73.1 tok/s; n-gram drafts plus MTP 71.7 (−2 %, ±0 % where the answer was the same); MTP with
  6 tokens and `spec-draft-p-min 0.5` 68.2 (−6 %). Details and the per-task figures:
  [model-choice.md](model-choice.md).

### Decision

`local-coder` stays as it is (MTP, 4 tokens); no change in `config\`. Noted in
[models.md](models.md) (MTP) and for Q4 in the [roadmap](roadmap.md): thinking is a quarter of
the output, a thinking budget would save little time.

### Next

The failures of `vergleich2` that were not timeouts were requirements of the task the model
overlooked (`extend`: names normalised like item names; `longcontext`: rules of single
countries). Next step: a point in the closing check that has the model go through the task
once more, requirement by requirement, measured against the run `english1`.

## 2026-11-18 afternoon: everything in English, a new GitHub page

The user's wish: everything in English, because the project is meant for international use,
and a nicer GitHub page.

### Done

1. **Terminal of Unzensiert:** texts in `config\unzensiert-texts.json` (before German in
   `unzensiert-texte.json`), numbers and dates in English (`1,873 tokens`,
   `Wednesday, November 18`), sample session `tests\agent-design.json` in English. The
   permission question shows the keys `y` and `a`; `j` and `i` still work.
2. **Styles renamed:** `ausbruch` → `breakout` ("Breakout", moods street/free/cloud),
   `nachtschicht` → `nightshift` ("Night Shift", moods workbench/ember/highbeam); quotes
   (`texts.quotes`, before `sprueche`), activity and done words, labels and pictures (FREE,
   CLOUD) in English. `formerNames` and `formerThemes` in `config\style.json` let
   `Install-Style.ps1` replace the entries of the German names; applied on the development
   computer (Windows Terminal profile, scheme and theme "Breakout", Claude Code themes
   `breakout-free`, `breakout-cloud`; the old theme files were removed by the script).
3. **What the model reads:** `config\coding-rules.md` (before `entwicklungsregeln.md`),
   `closing-check.md` (before `abschluss.md`, points `[docs]`, `[settings]`, `[cleanup]`),
   `second-look.md` (before `zweiter-blick.md`, answer words `ERROR`, `HINT`, `NO FINDINGS`; the
   parser still understands `FEHLER` and `HINWEIS`), workflows in `config\workflows\` (before
   `befehle\`, plugin `local` instead of `lokal`, `/review` instead of `/pruefen`), the reasons of
   the guard and the messages of the closing check and the second look.
4. **Project templates** in `templates\project\` (`shared\`, `__PACKAGE__`, placeholders
   `{{PACKAGE}}`, `{{PURPOSE}}`, `{{DATE}}`, `docs\decisions\`); fact status `confirmed` and
   `assumption` (the German `belegt` and `annahme` still accepted), the copy in the task
   `pinwechsel` updated (Test-Tasks requires the template version).
5. **Benchmark report** in English. The task ids `datenblatt` and `pinwechsel` and their German
   material stay, so that earlier results stay comparable; the rule `fakten` keeps its key in the
   results and is shown as `facts`.
6. **Documentation** in English with English file names (`architecture.md`, `setup.md`,
   `extending.md`, `models.md`, `model-choice.md`, `planner.md`, `projects.md`, `security.md`,
   `style.md`; this log was `protokoll.md`); all earlier log entries translated. `CLAUDE.md` in
   English with the rule "everything in English".
7. **GitHub page:** README rebuilt (badges, screenshots, highlights, comparison with Claude Code,
   quick start, usage, safety, status, limits); screenshots in `docs\images\`, rendered from
   `Show-AgentDesign.ps1` in a neutral sample folder; `docs\images\social-preview.png` for the
   social preview of the repository (set by hand in the settings of the repository); repository
   description and topics in English.

Found and fixed on the way: `Install-Style.ps1` wrote the profile in Windows Terminal with
`"guid": null` (the variable `$entryGuid` did not exist), so it never recognised its own profile.
It now uses the fixed GUID from `config\style.json`, and a profile named after a style (also a
former one) counts as its own.

### Checked

- `Test-Setup.ps1`, `Test-Agent.ps1`, `Test-Guard.ps1` (95 of 95), `Test-Templates.ps1`,
  `Test-Tasks.ps1` pass.
- All relative links and anchors in the Markdown files checked with a small script (only the
  links inside the project templates point to files that exist once a project is created).
- The design preview rendered again in both styles and looked at.

### Measured

Run `english1` (Unzensiert, `local-coder`, all eleven tasks once, English working rules,
closing check and second look; the closing check still began its message with the German word
"Abschlusspruefung"): **9 of 11 passed, 1,636 s, 259 rounds, rules 30 of 32**. For comparison
`vergleich2` (German texts, three runs per task): sum of the medians 1,629 s, 268 rounds,
27 of 33 passed, rules 88 of 96. The failures are known mistakes of the model: `psscript`
printed `"total": null` for `-Since` with `-Source` (as in `schleife1`), `longcontext` the known
mistake with Ireland. `extend` passed. The rule missed was `config` in `extend` and `psscript`,
as in every earlier run. With one run per task this shows no change through the English texts;
it is not a proof of equality.

## 2026-11-18 midday: better protection against loops

The reason was the loop of Unzensiert in `vergleich2`, `refactor` #1 (entry "morning:
comparison with repetitions"). Changes in `scripts\lib\AgentLoop.ps1` and `AgentTools.ps1`:

- **State of the files in the fingerprint:** a call counts as a repetition when name,
  arguments and result are the same and the files changed in the session have the same content
  (`Get-ChangedFilesState`). Before, every change deleted all fingerprints, and changing a file
  back and forth hid any loop.
- **Results without run times:** decimal numbers and `0x` addresses do not count in the
  comparison (`Get-ResultShape`). So `Ran 7 tests in 0.507s` counts as the same result as
  `0.493s`; whole numbers such as line numbers still count.
- **Changes without effect:** a Write with the content the file already has no longer writes
  anything, says so and does not count as a change. Such writes and edits with the same
  `old_string` and `new_string` are counted per request, whatever their arguments: a note from
  the third, a stop at the sixth (`maxRepeats`, text `notes.noEffect`).
- **Bug fixed:** Edit compared `old_string` and `new_string` with `-eq`, that is ignoring upper
  and lower case. An edit that only changes the case (`true` to `True`) was refused as "nothing
  to change". It now compares with `-ceq`. The pitfall is now among the pitfalls of PowerShell
  5.1 in `CLAUDE.md` and in the section "Structure" of `docs\unzensiert.md`.

Recomputed on the 33 recorded conversations of Unzensiert from `vergleich2`: the same calls ran
offline once through the old and once through the new rule. The old rule gave exactly the
course of the real run.

| Run | old rule | new rule |
|---|---|---|
| `refactor` #1 | one note (call 49), no stop; ended only at the time limit after 600 s | note at the 3rd edit without effect (call 48), stop at the 6th (call 54, after 13 of the 42 calls of the loop) |
| the other 32 | no note | no note, no stop |

Checks: Test-Setup; Test-Agent with new cases (file written back and forth, run times in the
result, Write with the same content, case in Write and Edit, edits without effect); Test-Agent
`-WithModel` (11 rounds, 27 s, as before).

Run `schleife1` with the new code (Unzensiert, `refactor`, `psscript` and `longcontext` twice
each): 3 of 6 passed, times within the range of `vergleich2` (`refactor` 208 and 216 s,
`psscript` 324 and 228 s, `longcontext` 308 and 269 s). The new rule only spoke up in
`psscript` #2, early in the session. At the 3rd edit without effect two notes came: the one on
the repetition (the old rule would have given it just the same) and the one on changes without
effect. At the 4th the second came once more. Then the model rewrote the file and went on
working normally: 24 of 24 own tests green, closing check. Nothing was stopped. The failures are
mistakes of the model in which the new rule played no part:
- `refactor` #2: left a temp file behind after a failed save (line 65 of the check); in this
  session there was no note and no change without effect.
- `psscript` #2: printed `"total": null` for `-Since` with `-Source`; its tests did not cover
  that.
- `longcontext` #1: the known mistake with Ireland.

## 2026-11-18: terminal of Unzensiert worked out

The user's wish: work out the design of Unzensiert further and in more detail, now that it no
longer rests on Claude Code. Description with a picture of all elements:
[style.md](style.md#the-terminal-of-unzensiert).

### Done

1. **New terminal** in three files: `scripts\lib\AgentUi.ps1` (welcome, activity line, title
   and progress of the tab, notes, input, status line, overviews, end of a request, farewell),
   `AgentUiMarkdown.ps1` (Markdown with word wrap, tables with aligned columns, code blocks in a
   frame with colours for 15 language families) and `AgentUiTools.ps1` (tools with sign,
   colour, tick and duration, diff with line numbers, tinted ground and marked characters,
   question in a frame). Text is built from pieces with colour, ground and attributes that can
   be measured and wrapped.
2. **The activity line moves during every wait:** streamed answer, commands and closing check
   ask for Esc ten times a second anyway (`Test-UiStop`); it is redrawn then. It also shows
   which tool call the model is writing right now (event `tool` of the stream, unused before).
3. **Texts in German** in `config\unzensiert-texte.json` (in English in the code before); what
   the model reads stays English. `Test-Setup.ps1` checks that every text the code asks for is
   there (112). (Since the same evening in English, `config\unzensiert-texts.json`.)
4. **Style section `agent`** in `ausbruch.json` and `nachtschicht.json` (today `breakout.json`
   and `nightshift.json`): picture, signs, colours per tool, words for finished requests, tint
   of the diffs.
5. **Results of the tools** also carry `info` (lines, files, return value, output of a command)
   for the display; the text to the model is unchanged.
6. **`unzensiert.ps1`:** terminal already before the server starts, its own welcome instead of
   the lines of `claude-local`, farewell with the numbers of the session, the old window title
   afterwards.
7. **`scripts\Show-AgentDesign.ps1`** shows every element with the sample session
   `tests\agent-design.json`, without a model, also in another style (`-Style`).
8. **Checks:** `Test-Agent.ps1` checks wrapping, diff, marking in the diff, colours of code (no
   character gets lost) and the preview; `Test-Setup.ps1` texts and style sections.

Built in a working folder of its own (git worktree), because the comparison `vergleich2` was
running and every task run reads `config\` and `scripts\` anew.

### Measured

Windows PowerShell 5.1, window 120 columns, while the benchmark was running: one frame of the
activity line about 4 ms (at most ten per second), one line of the answer about 2 ms, a
paragraph of 220 characters 4 ms, diff of the sample 11 ms, 60 lines with 8 changes 34 ms,
welcome the first time 480 ms (with `nvidia-smi`), status line 90 ms. Loading all scripts 265
instead of 235 ms.

### Checked

- `Test-Setup.ps1` and `Test-Agent.ps1` pass.
- Preview in "Ausbruch" and "Nachtschicht", 80, 100 and 120 columns rendered as pictures and
  looked at (own small terminal emulator with IBM Plex Mono).
- Answer piece by piece with pauses: activity line (27 redraws), raw and wrapped lines leave
  nothing behind; the final picture equals that of an answer in one piece.

Found on the way (now in [unzensiert.md](unzensiert.md#structure)): a function that answers
with `return , $list` must not also be called inside `@(...)` (otherwise a list in a list,
shown as `System.Object[]`), and PowerShell 5.1 cannot read `$t[($i + 1), $j]` as the argument
of a method.

### Not checked

In a real Windows Terminal window: title and progress ring on the tab, the bar behind your own
input after PSReadLine, the keys in the question and whether `✓ ✗ ✎ ✚ ⌕ ❯ ≡ ⎿` are one column
wide.

## 2026-11-18 morning: comparison with repetitions (`vergleich2`)

The more thorough comparison the user had asked for after the release: all eleven tasks, each
three times, `local-coder`, without the second look. Command
`Benchmark-Models.ps1 -Only local-coder -Label vergleich2 -Repeat 3 -Agent claude-local`, then
the same with `-Agent unzensiert`. This time `claude-local` ran first (06:40 to 08:30,
Unzensiert 08:30 to 10:03); in `vergleich1` it was the other way round. Raw measurement before
the tasks: 69.6 and 66.3 tokens/s generating, 993 and 975 reading.

| | Unzensiert | claude-local (Claude Code) |
|---|---|---|
| passed | 27 / 33 | 29 / 33 |
| time, sum of the medians per task | 1,629 s | 2,160 s |
| rounds, likewise | 268 | 418 |
| tokens written, likewise | 98,591 | 122,004 |
| all 33 runs | 5,528 s | 6,541 s |
| working rules | 88 / 96 | 86 / 96 |
| time limit (600 s) reached, files right | `refactor` #1 | `planner` #1 |

Table per task and assessment: [model-choice.md](model-choice.md). In short: Unzensiert was
faster on all eleven tasks (median). The difference in passing is within chance (Fisher's exact
test, p = 0.73). Runs at the time limit count as failed, as in `benchmark.md`.

The failures were looked at in the saved conversations (`<installRoot>\sessions`) and in the
working folders:

- **`extend`, Unzensiert #2 and #3:** `transfer("Bolt", ...)` found nothing, because the item
  name was not normalised there (`source_items.get(item, 0)`). Claude Code failed on the same
  mistake (`only 0 of Bolt in main`) in 2 of 28 runs so far (`stufe3`, `stufe3-befehl`). The
  agent had checked the new behaviour itself: first with a script, after the closing check with
  24 new tests (33 of 33 green). None called `transfer` with a capitalised name. A mistake of
  the model, not of the agent.
- **`longcontext`:** both agents made the same mistakes as in earlier runs (Ireland: upper
  limit; Spain and the Netherlands: `invoice`). Over all runs so far Claude Code passed the task
  in 6 of 24 cases.
- **`datenblatt`:** the same wrong value from the datasheet (HX-7) for both.
- **Time limit with Unzensiert, `refactor` #1** (solution passed anyway): after the closing
  check the model wanted to repair its own new test and went in circles for six minutes. It
  wrote `tests\test_tracker.py` four times with exactly the same content and tried 16 edits with
  `old_string` equal to `new_string`; in between the tests ran with the same error. The
  protection against repetition gave a note once but never got to stopping. Cause: every change
  to a file reset its counter, even a Write with the same content, and the test output never
  looked the same twice because of the run time (`Ran 7 tests in 0.507s`, `0.493s`, `0.496s`,
  each time with the same `TypeError`). To be improved next (done, entry "midday").

## 2026-11-18: first release v1.0.0

Published at the user's request, with `scripts\New-Release.ps1 -Version 1.0.0` and a text of
its own: tag `v1.0.0` on commit `aa4438a`, release
<https://github.com/MD220411/Unzensiert/releases/tag/v1.0.0>. Before that all six checks of the
script passed (Test-Setup, Test-Guard 95 of 95, Test-Agent, Test-Install, Test-Templates,
Test-Tasks). From now on the one-liner gets this release instead of `main`, and installations
with automatic updates bring in newer releases.

The update was checked against the real release, on two copies in the temp folder marked as
version 0.9.0. Each copy ran with its own scripts (`Get-LatestRelease`, `Get-UpdateBlocker`,
`Update-ProgramFiles`):

| Installation | found | Result |
|---|---|---|
| ZIP (unpacked, one file deleted) | `v1.0.0`, newer, no obstacle | ZIP downloaded and laid over it, `VERSION` 1.0.0, the deleted file back |
| git (shallow clone as by the installer, without tag) | `v1.0.0`, newer, no obstacle | tag fetched from GitHub and switched to, `VERSION` 1.0.0, no changes |

Not checked: the restart of `unzensiert` after the update and `Install-LlamaCpp` afterwards
(`Complete-ProgramUpdate`). That only works with a second release on a real installation.

Docs: the ZIP link in `README.md` and `docs\setup.md` now points to the newest release instead
of `main`, like the one-liner.

## 2026-11-17 night: Unzensiert – own agent instead of Claude Code, automatic updates

The user's wish: replace Claude Code in local use by a program of our own, to be more
independent; more efficient and better, with the same functions and the same look; plus
automatic updates for installations from GitHub that can be switched off. Decisions of the
user: name "Unzensiert" (command `unzensiert`), Claude Code stays for comparison
(`claude-local`), updates only from published releases.

### Done

1. **Agent** in PowerShell 5.1 without further dependencies (description
   [unzensiert.md](unzensiert.md)): `scripts\unzensiert.ps1`, `bin\unzensiert.cmd` and
   `scripts\lib\AgentApi.ps1` (JSON through the JavaScriptSerializer, streamed request to
   `/v1/chat/completions`), `AgentTools.ps1` (Bash, PowerShell, Read, Edit, Write, Glob, Grep),
   `AgentPrompt.ps1`, `AgentSession.ps1`, `AgentUi.ps1`, `AgentLoop.ps1`, `AgentRepl.ps1`.
   Settings `config\unzensiert.json`, system prompt `config\unzensiert-prompt.md`; it shares
   model, choice, rules, closing check, second look, tool set and workflows with `claude-local`
   through `config\agent.json`.
2. **Guard in its own process** through `scripts\hooks\GuardRules.ps1` (commit 0571e1d):
   2.7 ms per check instead of 280 ms for a hook process.
3. **Closing check** unchanged as a hook (`Check-Stop.ps1`); Unzensiert writes a transcript in
   the format of Claude Code. `Invoke-StopHook` now starts the hook as a process that Esc can
   stop and also returns `systemMessage`; the hook names the agent (`CLAUDE_LOCAL_AGENT`).
4. **Automatic updates** (`scripts\lib\Update.ps1`, `config\updates.json`, `VERSION`): at most
   once a day at start, only releases, with git (tag) or ZIP, then `Install-LlamaCpp.ps1` and a
   restart; never in folders with changes by hand or in development clones.
   `unzensiert --updates on|off`, `--update`. The installer asks once, `install.ps1` gets the
   newest release. Publishing: `scripts\New-Release.ps1`.
5. **Installer**: Unzensiert is the main command; Claude Code only on request (the question
   defaults to no), `Uninstall.ps1` also removes conversations and history.
6. **Benchmark**: `-Agent unzensiert|claude-local` (default `agent` in
   `config\benchmark.json`), field `client` in the results, columns agent, rounds, tokens in the
   report.
7. **Checks**: `scripts\Test-Agent.ps1` (without a model about 5 s; `-WithModel` with a small
   task and a summary), new cases in Test-Setup.

### Found and fixed on the way

- **Guard, since the first public version:** every command of one word (`ls`, `pytest`, `make`,
  also as part of `cd tests && pytest`) ended with `guard-error` and so with a question, in the
  benchmark with a refusal (list with one element in PowerShell). Fixed in commit 324cfcf, four
  new cases, Test-Guard 95 of 95. Earlier benchmark runs of `claude-local` may be affected if
  the model used such commands.
- **Byte order mark in the input of child processes:** on a UTF-8 console .NET writes a BOM
  into the input of a process with redirected input right at the start; the hook then read no
  JSON and let the model end unchecked. Child processes now start through
  `Start-ChildProcess` (`lib\Machine.ps1`).
- **Rights in the first trial run** (35 rounds, 57 s for a small thing): `python -c "a; b"` was
  split at the `;` inside the quotes and refused, and in mode `edits` the model was not allowed
  to delete a file, so it looked for detours for ten rounds. Now: splitting only outside quotes,
  file commands in the project folder count as file changes in `edits`, a note after three
  refusals, the end after nine. Afterwards 8 rounds in 24 s.

### Measured

Benchmark with both agents, run `vergleich1` (command:
`Benchmark-Models.ps1 -Only local-coder -Tasks screenshot,pinwechsel,datenblatt,extend,refactor -Label vergleich1 -Agent unzensiert`,
then `-Agent claude-local`):

| Task | Unzensiert | claude-local (Claude Code) |
|---|---|---|
| `screenshot` | 80 s, 16 rounds | 98 s, 22 rounds |
| `pinwechsel` | 80 s, 17 rounds | 123 s, 30 rounds |
| `datenblatt` | 105 s, 15 rounds | 124 s, 25 rounds |
| `extend` | 214 s, 21 rounds | 244 s, 34 rounds |
| `refactor` | 180 s, 19 rounds | 240 s, 48 rounds |
| **together** | **5 / 5 passed, 659 s, 88 rounds, 42,640 tokens, rules 22 / 23** | 5 / 5 passed, 829 s, 159 rounds, 48,858 tokens, rules 21 / 23 |

Unzensiert was faster on all five tasks (20 % less time altogether), needed 45 % fewer rounds
and 13 % fewer tokens written; both passed everything. The missed rules: for both `config` in
`extend`, for `claude-local` also `docstrings` in `refactor`.

Reservations: **one run per task.** Earlier repetitions of the same task with `claude-local`
varied by up to 30 % (`extend` 241 to 334 s in run `stufe4`), so the gap for a single task is
within the spread; that it goes in the same direction for all five speaks for a real difference
but does not prove it. Rounds are the requests to the model for Unzensiert, its figure
`num_turns` for Claude Code. Not measured: `longcontext` (summarising with a full context),
`psscript`, the older tasks, repetitions (`-Repeat 3`) and the second look (`-Git`).

Further measurements: guard 2.7 ms per check in its own process against 280 ms as a hook; first
request of a task 2,808 tokens (Claude Code about 26,000); cache of the server in a test run
8,629 of 8,719 tokens. Checks: Test-Agent (also `-WithModel`, with a summary), Test-Setup,
Test-Guard 95 of 95, Test-Install passed.

### Open

- Operation in the terminal (keys, input line, questions, Alt+V, Shift+Tab) is only checked
  automatically up to the output; the user should try a session.
- Publish the first release v1.0.0 when the user wants it (`scripts\New-Release.ps1 -Version
  1.0.0`); only then do the automatic updates take effect and `install.ps1` gets a release
  instead of `main`.
- Comparison on all tasks and with repetitions (`-Repeat 3`), also `longcontext` (summarising
  with a full context).

## 2026-11-17 evening: planner – computing the spread over cards and main memory

The user's wish: at installation the program should look at the equipment of the computer and
compute mathematically how best to spread the models over the resources. Built in the working
folder `Unzensiert-planer` (branch `planer`).

### Done

1. **Computation** (`scripts\lib\Planner.ps1`, description [planner.md](planner.md)): memory
   per device from `llama-fit-params --fit-print on` (estimate of llama.cpp for a given
   distribution) plus reserve, MTP addition and image encoder; time per token =
   Σ MiB read × µs/MiB per device; µs/MiB from a calibration with `llama-bench` (one run on the
   processor only, one run per card "this card first", a linear system of equations). Search
   per context size: fill the fastest card first and put it last in `--device` (output and MTP
   layer there), with MoE move experts out first (`--n-cpu-moe`), image encoder where room
   remains, otherwise the processor. Chosen: the largest context from 64k with at most 15 % less
   speed than the fastest.
2. **`scripts\Plan-Models.ps1`** (`-Model`, `-Recalibrate`, `-Verify`, `-Show`): writes the
   options into `config\machine.json` (`fit: off`, `gpu-layers`, `device`, `tensor-split`,
   `n-cpu-moe`, `mmproj-device`/`mmproj-offload`, `ctx-size`), plus `plans` and `calibration`.
   `-Verify` loads and tests; if a model does not load or crashes under a request (error 500),
   it plans again with 1 GB more reserve. It takes the card values of a MoE model from the
   calibration of a dense model.
3. **`config\planner.json`**: reserve 1024 MiB per card, MTP addition 1408 MiB, main memory
   reserve 6 GB, context sizes 128k/96k/64k/32k, `minCtx` 64k, tolerance 15 %.
4. **Installer**: after the download `Plan-Models.ps1 -Model <model> -Verify`; if that fails,
   `Clear-ModelPlan` takes the options out again (llama.cpp distributes the model itself).
5. **`Measure-Setup.ps1 -Planned`**: the planner for exactly the cards made visible.
6. **Tests**: `Test-Install.ps1` +15 checks with a simulated memory model (order, full fast
   card, choice of context, experts, image encoder, solving the calibration, implausible
   calibration); `Test-Setup.ps1` checks `planner.json` and that `llama-fit-params.exe` and
   `llama-bench.exe` are there.

### Measured

- Calibration on both cards (`local-coder`): RTX 5070 Ti 1.38 µs/MiB (≈ 760 GB/s), RTX 3060
  3.57 µs/MiB (≈ 294 GB/s), main memory 19.9 µs/MiB. Ratio of the cards 2.6, manufacturer
  figures 2.5. Three splits by hand (70/30, 55/45, 45/55: 31.5 / 27.3 / 25.1 tok/s with
  `llama-bench`) give the same difference (2.16 and 2.10 µs per MiB).
- Extra memory the estimate does not know (split 30/36, without a limit): first card +650 MiB
  (CUDA context), last card +2025 MiB (of which ≈ 1375 MiB MTP draft). The RTX 5070 Ti has a
  fixed limit at 15.58 GB; above it the driver silently moves memory out (sysmem fallback). The
  setting of 70/30 by hand sat at this limit to the MiB.
- **Crash with 512 MiB reserve**: after the start the router measures the other models with
  processes of their own (`measure_next`, ≈ 550 MiB CUDA context each); at that moment
  `local-coder` died (status -1073741819). Hence a reserve of 1024 MiB.
- Results (`Test-Model.ps1`, speed with MTP; tool calls and images OK everywhere):

  | Cards | Model, context | `--fit` | By hand 70/30 | Planner |
  |---|---|---|---|---|
  | both | `local-coder`, 128k | 44 | 58.5 / 61.8 | 65.7 / 70.7 (37 + 29 units) |
  | RTX 5070 Ti alone | `local-coder`, 64k | 20.9 | | 21.8 |
  | RTX 5070 Ti alone | `local-fast`, 64k | 97.1 | | 105.7 |
  | RTX 3060 alone | `local-fast`, 64k | 62.2 | | 65.0 |

  Free choice of the planner: RTX 5070 Ti alone `local-coder` 96k at 18.7 tok/s; RTX 3060
  alone `local-fast` 128k at 58.2; RTX 3060 with 4 GB free 128k at 53.6. The setting by hand
  with the reverse order did not load (too full).
- Calibration with a MoE model unreliable: RTX 3060 0.55 µs/MiB (impossible), RTX 5070 Ti
  implausible (substitute value). Without consequences for one card; with several cards the
  planner takes the values of a dense model.
- Without a model: `Test-Setup`, `Test-Install`, `Test-Guard` (91), `Test-Templates`,
  `Test-Tasks` passed.
- **Applied to the development computer** (`Plan-Models.ps1 -Verify`, all three agent models,
  setting by hand saved in `<installRoot>\run\machine.json.vor-planer`): `local-coder` 128k
  66.9 tok/s, `local-qwen38` 128k 70.5, `local-fast` at first 64k with 200.8. A consequential
  error noticed: `claude-local` takes the smallest window of the `/model` choice, every session
  would have shrunk to 64k. Correction: plan the default model first, the other models of the
  choice get at least its context. Afterwards `local-fast` 128k at 171.2 tok/s (by hand before
  83 to 140), experts of one layer in main memory. Predicted for 128k was 32 % less than for
  64k, measured about 15 %: the computation is too pessimistic with experts moved out.

### Open

- Real computers with other cards, AMD/Intel, more than two cards: unchecked.
- `-Verify` does not check whether a plan moves memory out (only whether it runs).
- The formula takes no context depth into account; whether `local-coder` stays as reliable in
  the benchmark with the plan is not measured (only `Test-Model.ps1`).

## 2026-11-17: installer for any Windows computer

The user's goal: everyone should be able to download, install and use the project, as simply as
possible. Decisions of the user: NVIDIA as the tested path, AMD and Intel experimental through
Vulkan; installer and quick start in English, documentation still German (English since
2026-11-18); start by one-liner and by ZIP with a double click. Built in a working folder of its
own (`git worktree`, branch `installer`), because a benchmark from the project folder was
running at the same time.

### Done

1. **Project and computer kept apart.** New file `config\machine.json` (not in the repository)
   with the values of this computer; `lib\Config.ps1` lays its sections over the files in
   `config\` (`Read-Config`, `Merge-ConfigObject`, `null` removes a key). Removed from the
   shared files and moved to `machine.json`: `installRoot` and `projectsRoot` of the
   development computer, `package`, `gpu-layers 999`, all `tensor-split`, `mmproj-device` and
   `device`, the Q4_K_M file of the autocomplete model. New defaults:
   `%LOCALAPPDATA%\claude-local`, `%USERPROFILE%\Projects`, `modelsDir` and `workDir` empty =
   under `installRoot`. Without details on the split llama.cpp distributes the model itself
   (`--fit`, the default).
2. **Guard without fixed drives.** `config\guard.json` names `%CLAUDE_LOCAL_ROOT%` and
   `%CLAUDE_LOCAL_PROJECTS%`; `scripts\_common.ps1` sets both, the hooks read them through
   `scripts\hooks\HookEnvironment.ps1` (when started by hand, from the settings).
   `machine.json` is protected as well. `Test-Guard.ps1` sets fixed sample folders from
   `tests\guard-cases.json` (`machine`), `{repo}` stands for the repository: 91 cases.
3. **Downloads with a source.** Every profile in `config\models.json` has `role` and
   `download` (Hugging Face repository, fixed commit, size, SHA-256 per file), generated from
   the answers of the API, not copied. `scripts\Get-Model.ps1` downloads resumably through
   `<name>.part` and renames only after size and checksum (`lib\Download.ps1`). New computers
   get the autocomplete model as Q8_0 from `ggml-org`.
4. **Recognising hardware.** `lib\Machine.ps1`: graphics cards (`nvidia-smi`, Windows display
   adapters, device list of llama.cpp without integrated graphics), main memory, free space, Git
   Bash, Claude Code. `config\setups.json`: tiers by graphics memory. With `package: auto`
   `Install-LlamaCpp.ps1` chooses the package by card (`packages` in `server.json`), checks with
   `--list-devices` and falls back (CUDA 13.5, CUDA 12.4, Vulkan); before unpacking it empties
   the program folder (only `b<number>`) so that no second backend loads, and stops a running
   server.
5. **Installer.** `scripts\Install.ps1` (seven steps, asks before every installation and every
   download, `-Plan`, `-Yes`, `-InstallRoot`, `-Model`), `Install.cmd` for a double click,
   `install.ps1` as one-liner (git clone or ZIP to `%LOCALAPPDATA%\Programs\claude-local`,
   without `exit`), `scripts\Uninstall.ps1` with `Uninstall.cmd` (deletes only what the
   installer created). Questions and step display in `lib\Dialog.ps1`.
6. **The agent on other computers.** `claude-local` finds Claude Code even without an updated
   PATH, starts with the first downloaded model when the default model is missing, shows only
   downloaded models in `/model` and replaces `Bash` by `PowerShell` without Git Bash. The
   second look checks with the default model when `local-qwen38` is missing.
   `Test-Model.ps1 -NoLog` does not write into the log in the repository (otherwise it would
   block a later `git pull`) and ends with code 1 on `FAILED`; `Get-GpuMemory` without
   `nvidia-smi` gives `n/a`.
7. **Tests.** New `scripts\Test-Install.ps1` (43 checks without download and model:
   `machine.json`, device list, choice of tier, tools, download entries, dry run
   `Install.ps1 -Plan` for an empty computer, one-liner without `exit`). `Test-Setup.ps1`
   reports profiles that are not downloaded as a note instead of an error, checks the download
   entries against the files of every profile and `setups.json`. `.gitattributes`: `.cmd` with
   CRLF.
8. **Docs.** README with an English quick start; `setup.md` describes installer, tiers,
   `machine.json`, updating and uninstalling; updated `architecture.md`, `backend.md`,
   `models.md`, `agent.md`, `security.md`, `projects.md`, `extending.md`, `CLAUDE.md` (rules:
   project and computer kept apart, the repository is public, `Test-Install.ps1`).

### Measured and checked

- Without a model: `Test-Setup`, `Test-Install` (43), `Test-Guard` (91), `Test-Templates`,
  `Test-Tasks` passed. `Install.ps1 -Plan` on this computer takes over the existing install
  folder, recognises both cards (28562 MiB) and the existing model files; for an empty computer
  it suggests `claude-local` on the drive with the most room and `local-coder` (16.9 GB).
- Origin of the image encoders: SHA-256 of the three `mmproj` files recomputed, matches Hugging
  Face. That settles the open point "source and checksums of the `mmproj` files". All model
  files have byte-identical sizes to the sources.
- Claude Code without signing in: with an empty configuration folder (`CLAUDE_CONFIG_DIR`) and
  a stub server as `ANTHROPIC_BASE_URL`, `claude -p` answers at once, without asking for a
  login (Claude Code 2.1.326). The interactive first setup (colour theme, trust) cannot be
  checked this way.
- **Hardware tiers** with the new `scripts\Measure-Setup.ps1` (only chosen cards visible,
  general settings without fine-tuning, `Test-Model.ps1` plus prompt speed with 26,177 tokens).
  All runs: tool calls OK, image input OK.

  | Simulated | Profile, context | Generation | Prompt | Session start |
  |---|---|---|---|---|
  | both cards (28 GB), without fine-tuning | `local-coder`, 128k | 44.4 tok/s | 815 tok/s | 32 s |
  | both cards, 2560 MiB free each (≈ 23 GB) | `local-coder`, 64k | 49.4 tok/s | 882 tok/s | 30 s |
  | RTX 5070 Ti alone (16 GB) | `local-coder`, 64k | 20.9 tok/s | 572 tok/s | 46 s |
  | RTX 5070 Ti alone (16 GB) | `local-fast`, 64k | 97.1 tok/s | 775 tok/s | 34 s |
  | RTX 3060 alone (12 GB) | `local-coder`, 64k | 10.8 tok/s | 184 tok/s | 143 s |
  | RTX 3060 alone (12 GB) | `local-fast`, 64k | 62.2 tok/s | 244 tok/s | 107 s |
  | RTX 3060, 4096 MiB free (≈ 8 GB) | `local-fast`, 32k / 64k | 55.8 / 56.8 tok/s | 211 / 207 tok/s | 124 / 126 s |
  | no card (Core i9-14900K) | `local-fast`, 32k | 25.9 tok/s | 74 tok/s | 354 s |

  Consequences for `config\setups.json`: 16 GB gets `local-coder` (more reliable, 21 tok/s),
  `local-fast` as the named alternative; 12 GB gets `local-fast`; 8 GB gets 64k instead of 32k
  context, because it runs just as fast. Without fine-tuning `local-coder` is a quarter slower
  on both cards than with its own split (44 instead of about 60 tok/s); the fine-tuning stays
  in `machine.json` of this computer. The private memory of the model process was between 10.4
  and 19.5 GB with parts moved out; with a full card Windows shows no reliable value on this
  computer.
- **End to end on this computer:** `Install.ps1 -Yes` from the project folder (repair): takes
  over folder, package and fine-tuning, downloads nothing, `Test-Setup` passed, `local-coder`
  61.8 tok/s, tool calls and image input OK.
- **Bug found and fixed (closing check):** a run of `claude-local -p` in the repository hung in
  a loop for over 4 min. Cause: Claude Code 2.1.326 writes the descriptions of the tools
  (`{"name":"Edit","description":...}`) and the previous messages with every request into the
  history. `Check-Stop.ps1` counted every `"name":"Edit"` as a write call, reported "You changed
  files" after pure reading, and the model then wanted to touch up files, which `-p` refused
  without permission, again and again. Now only `tool_use` blocks count, every call id once;
  two new cases in `Test-Setup.ps1`. Counter-check in a test folder: before 3 rounds with a
  wrong reminder, afterwards 2 rounds, 7 s. Unclear since which version of Claude Code it is
  like that: benchmark times of the last runs may contain unnecessary reminder rounds.

### Open

- Not checkable on this computer: a fresh Windows computer (interactive first start of Claude
  Code, `winget` for Git, package choice with an old driver), AMD and Intel through Vulkan, the
  agent with the tool `PowerShell` instead of `Bash`, a real 24 GB or 8 GB card. A second
  computer (acquaintances, feedback through GitHub issues) would be the next test.
- The quality of the tiers is only checked through `Test-Model.ps1`, not in the benchmark: does
  `local-coder` run just as reliably with 64k instead of 128k context?

## 2026-11-17: "Ausbruch" (today "Breakout") in more detail and in more places

### Done

1. **Picture of characters with details** (`lib\CharArt.ps1`): light from above (lighter at the
   top, darker at the bottom), shadow bottom right of `:;.`, drips from the bottom edges (`|!:`
   with a drop), sparks `✦ ✧ * +`. The picture is now 10 instead of 7 rows high. Split into
   `Get-CharArtCells` (grid), `Format-ArtCells` (terminal) and `Save-ArtCellsImage` (PNG).
2. **Wall of characters** behind the terminal: `New-CharWall` draws FREI (today FREE) at the
   bottom right and sprayed characters around it; `Install-Style.ps1` saves it as `wand.png`
   (today `wall.png`) and enters it as the background picture of the profile (20 % opacity,
   `terminal.wall`).
3. **More places in the style:** sprayed line under every picture, a quote with every new shell
   (`texts.sprueche`, today `texts.quotes`), sprayed separators and characters flying away at
   the end of every prompt and status line (`trail`), picture WOLKE (today CLOUD) in cyan before
   `claude`, farewell with the duration of the session after `claude-local`
   (`Get-LocalLookFarewell`), eight more activity words.
4. **`Test-Setup.ps1`:** the cloud picture stays one colour (counter-check: colourful → 190
   cells outside), sprayed line and trail in the requested width, size of the wall.

### Measured

Picture UNZENSIERT at the first drawing about 240 ms (before 145 ms), afterwards about 75 ms;
FREI about 35 ms; wall about 310 ms when installing. Not checked: the effect in a real window.

## 2026-11-17: new look "Ausbruch" (today "Breakout")

### Done

1. **Second style "Ausbruch"** (`config\styles\ausbruch.json`, today `breakout.json`):
   colourful, free, rebellious. Pictures made of coloured letters and characters instead of
   pixels: above the shell the word UNZENSIERT, before every session of `claude-local` the word
   FREI, set in a block font, filled with random characters, coloured through a colour wheel
   of seven colours; overspray around the letters, to the right characters break out and fly
   away. Moods: Straße (shell), Frei (local, the whole colour wheel), Wolke (cloud, only cyan)
   – today Street, Free, Cloud. Sprayed gauges, colourful folder name, changing prompt sign,
   own themes for Claude Code, rebellious activity words, a colour wheel as tab icon
   ([style.md](style.md)).
2. **Styles switchable:** `config\style.json` only chooses the style (`active`) and holds what
   all share (profile GUID, variable `CLAUDE_LOCAL_LOOK` instead of `NACHTSCHICHT_MODE`, ending
   of the backups). The previous content lies next to it as `config\styles\nachtschicht.json`
   (today `nightshift.json`), with `shell.mode`. `Install-Style.ps1` takes the entries of all
   styles out before it writes the active one.
3. **New `scripts\lib\CharArt.ps1`** (pictures of characters); `lib\Style.ps1` with colour
   wheel, sprayed gauges and `Get-ShellModeName` instead of a fixed `werkbank`.
4. **Status line:** reads stdin also with a leading BOM (before, an empty line without model
   and context when a caller sent one).
5. **`Test-Setup.ps1`** checks style files, block font, picture width, gauges and the status
   line.
6. "Ausbruch" is installed and active; a second run of `Install-Style.ps1` changes nothing.

### Measured

Picture UNZENSIERT at the first drawing about 145 ms, afterwards about 50 ms; picture FREI about
23 ms; local status line about 480 ms. Not checked: the look in a real window.

## 2026-11-17: second look in the benchmark, first part (run `h3-qwen38`)

### Done

1. **Benchmark for the second look:** `-ReviewModel` chooses the reviewer for a run,
   `-ExtraSeconds` extends every time limit by the review, every run records its reviews from
   `review.log`. During the run the computer does not go to sleep. Trial run `h3-probe`:
   `datenblatt` passed, one second look, 67 s, no finding.
2. **Planned:** `local-coder` on seven tasks (`extend`, `refactor`, `psscript`, `screenshot`,
   `longcontext`, `datenblatt`, `pinwechsel`), three times each, with `-Git` and
   `-ExtraSeconds 300`. Once `local-qwen38` reviews (`h3-qwen38`), once `local-coder`
   (`h3-coder`).
3. **Broken off after 9 of 42 runs:** at 17:07 a parallel session switched the look
   (`config\style.json`, `scripts\lib\Style.ps1`). After that `claude-local` broke off at once
   (`Set-Item` in `Style.ps1:175`, `modeVariable` empty). The benchmark still checked the
   unchanged task files and entered 33 runs with 0 s as "failed". I removed these 33 runs from
   `results.jsonl`; the record `h3-qwen38` contains only the 9 real runs and the reason in the
   field `error`. `h3-coder` did not run.
4. **Safeguard:** if `claude-local` ends without a result line, `Benchmark-Models.ps1` now stops
   with exit code 1. The runs before stay in the record, the reason is in the field `error`.

### Result of the 9 valid runs (reviewer `local-qwen38`)

| Task | passed | time with second look | `b12433` without | reviews | findings |
|---|---|---|---|---|---|
| `extend` | 3 / 3 | 1102 s | 886 s | 3, 50 to 144 s each | 1 ERROR, 1 hint |
| `refactor` | 3 / 3 | 1290 s | 799 s | 3, 98 to 134 s each | 5 hints |
| `psscript` | 2 / 3 | 2056 s | 1221 s | 3, 142 to 165 s each | 1 hint |
| together | 8 / 9 | 4448 s | 2906 s | 9, 126 s on average | 1 ERROR, 7 hints |

- **The one ERROR was a real hit:** in `extend #2` a new test was called
  `add_to_default_warehouse` without `test_` and never ran. The agent checked the finding,
  confirmed and fixed it (37 instead of 36 tests). The check of the task would not have noticed;
  the run had passed already.
- **No false alarm:** no ERROR report that was not right. The 7 hints only went to the user and
  did not hold the agent up.
- **One mistake overlooked:** `psscript #3` failed (an invalid `-Since` with `-Format json` ends
  with exit code 1 instead of 2). The reviewer reported nothing.
- **Cost:** 53 % more time for these three tasks. About 1130 s of it go to the nine reviews
  themselves (including switching models). The remaining roughly 410 s are not assigned: spread
  of the runs or the git repositories (not measured separately).
- **Limits:** 9 runs, one reviewer, only tasks without reference to facts. Whether
  `local-coder` as reviewer finds more and whether the second look helps with `datenblatt` and
  `pinwechsel` is open. The choice of reviewer stays with `local-qwen38` until the complete
  measurement.

## 2026-11-17: first public version

### Done

1. The repository is public and begins with a new git history. The previous 23 commits are in
   a private archive.
2. Licence MIT (`LICENSE`), section "License" in the README.
3. Searched beforehand: no keys or passwords in files and history, commits only with the
   anonymous GitHub address. Personal paths in the log replaced by `%USERPROFILE%`.
4. References to commit `fbb8c80` (state before the switch to llama.cpp) concern the history
   before the public version; it is not published.

## 2026-11-17: hardening H4 – benchmark tasks for faithfulness to facts and consistency

### Done

1. **`datenblatt` (datasheet):** driver for the made-up sensor HX-7 after
   `docs/datenblatt-hx7.md`. Next to it lie the driver and the datasheet of the HX-5, and the
   HX-7 datasheet calls it "pin-compatible". Differences: address 0x3A instead of 0x44,
   measurement only on command, status bits DRDY and ERR, low byte first, another formula,
   saturation at 100 %. The check simulates the sensor exactly after the datasheet.
2. **`pinwechsel` (pin change):** pump from GPIO17 to GPIO23 (pin 16), rain sensor with an open
   collector on GPIO17 (pin 11, needs a pull-up), no watering when it rains. The check requires
   all places to be consistent: `config/pins.json`, `DEFAULT_PINS`, README, wiring plan with
   header pin, `facts.json` and `check_facts.py`, own tests. The project brings a check command
   and fact comparison along.
3. **Rule `fakten` (facts)** in `benchmark\lib\rulecheck.py` and in the report: new fact with a
   source in `facts/facts.json`.
4. **`check_facts.py`** also recognises keys in quotes in every file (`"pumpe": 17` in a Python
   dict) and table rows with exactly one pin and exactly one known label
   (`| Pumpe (Relais IN1) | GPIO17 | 11 |`).
5. **`Test-Tasks.ps1`** checks that copies of `check_facts.py` and `Check.ps1` in tasks match
   the version of the template.

### Measured (without a model)

- `Test-Tasks.ps1`: both tasks fail in their starting state, the reference solution passes with
  all five rules; also with `-Overlay project`.
- Typical failed attempts fail. `datenblatt`: HX-5 copied, wrong byte order, ERR ignored.
  `pinwechsel`: README not updated, fallback value in the code forgotten, wrong header pin in
  the plan, pull-up forgotten. The first two of `pinwechsel` are also reported by
  `check_facts.py`, so by the closing check.
- `check_facts.py` on the HackMD copy: still all built-in errors found, no new false alarms; a
  table error (IR LED on GPIO26) is now recognised.
- `Test-Setup.ps1`, `Test-Templates.ps1`, `Test-Tasks.ps1` passed.

### Measured with a model (run `h4`, `local-coder`, three times each, without the second look)

| Task | Passed | Times | Rules |
|---|---|---|---|
| `datenblatt` | 3 / 3 | 129, 198, 121 s | 12 / 15 |
| `pinwechsel` | 3 / 3 | 103, 105, 130 s | 15 / 15 |

- `fakten` 6 / 6: in every run the model entered the new facts with their source. In
  `datenblatt` there were seven HX-7 facts with the section given, without the task asking for
  it.
- The three violations of `nodeadcode` (all in `datenblatt`) were false alarms. They were worked
  examples in tests like `# raw_t = 18304 -> T = 18304/256 - 50 = 21.5`. One contained a
  leftover of thinking ("wait let me use a bigger value"). Sharpened afterwards: in Python a
  comment line only counts as code if it compiles as Python. With the new check all three runs
  are clean. The saved result of `h4` holds the old value.
- **Assessment:** `local-coder` shows neither class of errors from the real work on these
  tasks when datasheet and facts file are in the project. The tasks are smaller than the real
  firmware (2 devices, over 20 files). So it is open whether the difference is due to the size
  or to the facts file and the rule. A comparison run without `facts\` and without the rule is
  missing.

### Afterwards

- **Switch `-Git` for `Benchmark-Models.ps1`:** working folders become git repositories with the
  task files as the first commit, so that the second look runs in the benchmark as well
  ([extending.md](extending.md)).

## 2026-11-17: hardening H3 – second look by a second local model

### Done

1. **`scripts\Invoke-Review.ps1`** with the building blocks in `scripts\lib\Review.ps1`: the
   uncommitted change (diff against `HEAD` and new files), the task from the history of the
   session, `CLAUDE.md`, `facts\facts.json` and the changed files in full in one request to
   `local-qwen38`. Answer form `FEHLER | ...` and `HINWEIS | ...` (since 2026-11-18 `ERROR` and
   `HINT`). Review instructions in `config\zweiter-blick.md` (today `second-look.md`),
   settings under `review` in `config\agent.json`, log `<installRoot>\logs\review.log`.
2. **Closing check, step 3:** once per answer, when check command and reminder have nothing
   open any more, even if the model changes nothing more after the reminder. Errors go back to
   the model, pure hints to the user. The time limit of the hook grows by `timeoutSeconds` +
   60 s.
3. **`Test-Setup.ps1`:** nine cases without a model: splitting the answer, counting diff and new
   files, no git, task from the history, time limit of the hook.

### Measured

On a git copy of `HackMD`, a change of 20 lines (IR LED moved, `ir_send_repeat` added) and five
built-in errors. Table in [agent.md](agent.md), section "Second look". In short:

- `local-qwen38`, three runs: off-by-one, contradiction in the README and outdated header
  comments found every time. Milliseconds instead of ticks and the made-up statement "5V
  tolerant" never found. 33 to 87 s.
- `local-coder` as reviewer, two runs: in addition the ticks both times, the 5V statement once.
  76 to 128 s.
- Error-free version of the same change: no finding in four runs.
- End to end through `Invoke-StopHook`: stop 1 reminder, stop 2 second look (53 s) with the
  off-by-one error, stop 3 the end.
- `Test-Setup.ps1` passed.

### Errors and findings

- **Windows PowerShell 5.1 and `git` on stderr:** with `ErrorActionPreference = 'Stop'` even the
  warning about line endings becomes a break-off, also with `2>$null`. So `Invoke-Git` uses
  `Continue`.
- **Threshold:** the test change with real errors had 27 lines (error-free version). The
  threshold of 30 planned first would have skipped it; now 20 (assumption).
- **`local-qwen38` did not find the made-up 5V statement in four of four runs.** Against made-up
  facts the facts file with sources (H1) stays the safety net; the second look mainly catches
  logic errors and contradictions.

### Open

- Measure the choice of reviewer (`local-qwen38` against `local-coder`) on several tasks (H4).
- How long switching models takes in a real session (reloading and reading in the conversation
  of `local-coder` again) is not measured.

## 2026-11-17: hardening H1 and H2 – facts with sources, comparison across files

### Reason

Hardening programme from the real work on the ESP32 project `HackMD` ([roadmap.md](roadmap.md),
section "Hardening"). For H3 the user chose the local variant A.

### Done

1. **`facts\facts.json` in every new project** (template `gemeinsam\facts\`, today
   `shared\facts\`): facts with `id`, `value`, `source` or `"status": "annahme"` (today
   `"assumption"`), for pins `device`, `direction`, `labels`; `code` names names in code and
   configuration that carry the value. Description `facts\README.md`.
2. **`scripts\check_facts.py`** as step "Facts" in the check command of both templates
   (PowerShell template: optional, if Python is missing). Checks: source present, values in the
   code equal (numbers as numbers, pins in every spelling), pins in the documentation with the
   right signal, no unknown pin, no pin twice per device, board profile. Replaces the first draft
   of Nov 16 (only pins, one device).
3. **Board profile `facts\boards\esp32.json`**, backed by the local ESP-IDF 5.1 (`soc_caps.h`:
   no GPIO20, 24, 28 to 31, GPIO34 to 39 input only; `spi_pins.h`: GPIO6 to 11 flash) and the
   datasheet (strapping pins 0, 2, 5, 12, 15).
4. **Rule "check facts instead of guessing"** in `config\entwicklungsregeln.md` (today
   `coding-rules.md`) and in the `CLAUDE.md` of both templates.
5. **`Test-Templates.ps1`:** new files present; a contradiction to `facts.json` and a fact
   without a source make the check command fail, after the correction it passes.

### Measured

- On a copy of `HackMD` with 25 facts for two devices (controller and ESP32-CAM agent): the
  comparison found five pins mentioned in the documentation without an entry (list of free pins
  in `wiring.html`, ADC channels in a comment), passed afterwards. All eight built-in errors
  found: pin changed in README and header, buffer size changed in only one of the two
  firmwares, flash pin, output on an input pin, pin GPIO31 that does not exist, fact without a
  source, pin not recorded.
- Spellings: Python with a type annotation, PowerShell, JSON, C with `GPIO_NUM_`, hex against
  decimal, voltage with and without unit; `LED_PIN == 5` does not count as an assignment.
- `Test-Templates.ps1` passed (both languages, 21 checks each).

### Open

- Whether the model keeps the facts file up to date on its own and follows the rule: H4.
- `HackMD` itself is not retrofitted (only the copy in the scratchpad).

## 2026-11-16 midday: llama.cpp b12433 (G5), preparing the thinking budget (Q4)

### Done

1. **Build change b12359 → b12433** after the procedure in [backend.md](backend.md);
   `config\server.json`, `backend.md`, `architecture.md` and `README.md` updated.
2. **Comparison profiles for Q4:** `local-coder-rb2048`, `-rb512` and `-rb0` (same file,
   `reasoning-budget` 2048, 512, 0) in `config\models.json` and `config\benchmark.json`. Remove
   them again after the measurement.

### Measured

- `Test-Model.ps1` `local-coder` on b12433: 58.7 tok/s (MTP 60 % accepted), tool and image fine,
  15596 and 10417 MiB. The same as on b12359 (59.3).
- The five tasks three times each, run `b12433`: **13 / 15 in 4463 s**, rules 60 / 66 (91 %).
  Comparison `stufe4` on b12359: 14 / 15 in 4903 s, 89 %. The failures only in `longcontext`
  (1 / 3 instead of 2 / 3); with three runs that is no solid difference. The new build stays.
- Only speed, no quality yet: `local-coder-rb2048` 57.5 tok/s, `local-coder-rb0` 72.8 tok/s (82 %
  of the MTP drafts accepted instead of 60 %).

### Open

- Measure Q4 on the tasks (`planner` and the five newer ones), then remove the profiles `-rb*`.

## 2026-11-16: fine-tuning, first part (stage 4 of the roadmap)

### Reason

The user released stage 4 and then asked to finish quickly so as to work with the coder. Done
are E1, E2, G1, G2 and Q9; Q5 is begun.

### Done

1. **`config\models.json`:** `mmproj-device: CUDA1` and `ctx-size: 131072` for `local-coder`,
   `local-fast` and `local-qwen38`; new comparison profile `local-coder-q5` (Q5_K_M, 64k, split
   66/34).
2. **Closing check:** `Check-Stop.ps1` reads the files changed in the answer from the history
   and leaves out points of the reminder that they settle (`reminderPoints` in
   `config\agent.json`, points `- [name]` in `config\abschluss.md`, today `closing-check.md`).
   If no point is open, no reminder comes. Two new cases in `Test-Setup.ps1`.
3. **Q5_K_M downloaded** from the source of the previous model (18.4 GiB), SHA-256
   `9d309b8f...5a4285` equal to the figure of the source, hooked in with `Add-Model.ps1`.

### Measured

Tables and assessment: [model-choice.md](model-choice.md), first section. In short:

- Image encoder on the 3060: 1.2 GB free on the 5070 Ti, images just as fast.
- 128k context: 15.6 and 10.4 GB, speed the same; all three profiles load.
- GPU split at 64k: 79/21 brings 65.5 instead of 61 tok/s; rejected in favour of the context.
  MTP length: 4 stays the best value.
- Run `stufe4` (128k, more economical reminder): 14 / 15 in 4903 s, rules 59 / 66 (89 %), README
  and test 15 / 15; `longcontext` 2 / 3. Before (`stufe3b`): 12 / 15 in 5951 s, 85 %.
- Finally: `Test-Model.ps1` 59.3 tok/s, tool call and image fine, 15596 and 10417 MiB;
  `Test-Setup.ps1` passed; `Test-Guard.ps1` 89 of 89.

### Errors and findings

- **Sleep during a measurement.** The second run of `stufe4-128k` stands in the report with
  41474 s; the value is useless.
- **The smallest window counts.** `claude-local` tells Claude Code the smallest `ctx-size` of the
  profiles in the model choice. For the measurement with 128k all three profiles therefore had
  to be switched.
- **Q5_K_M with 96k does not load** (`failed to create context`); nor does `82,18` as the split.

### Open

- Stage 4, the rest: E3 to E5, G3 to G5, Q4, Q6; quality of Q5 against Q4.
- `local-fast` and `local-qwen38` with 128k on the tasks; tab completion of Continue next to
  `local-coder` with 128k.

## 2026-11-15 evening: way of working (stage 3 of the roadmap)

### Reason

The user released stage 3: project template (N1), short `CLAUDE.md` (N2), decision files (N3),
one check command per project (N4), fixed workflows as commands (N5), a check after every answer
(Q3), notes on PowerShell 5.1 (Q8).

### Done

1. **Notes on PowerShell 5.1** as a section in `config\entwicklungsregeln.md` (today
   `coding-rules.md`).
2. **Closing check:** `scripts\hooks\Check-Stop.ps1` as a `Stop` hook. After an answer with
   file changes it runs the check command of the project (if there is one) and returns errors to
   the model, at most three times; once per answer it reminds of test, README, settings and
   cleanup with `config\abschluss.md` (today `closing-check.md`). Settings under `stopCheck` in
   `config\agent.json`, building blocks in `scripts\lib\Quality.ps1`.
3. **Workflows** `/lokal:feature`, `/lokal:bugfix`, `/lokal:pruefen` (today `/local:feature`,
   `/local:bugfix`, `/local:review`) as a plugin in `config\befehle\` (today
   `config\workflows\`), loaded with `--plugin-dir` only for `claude-local`.
4. **Project template** in `templates\projekt\` (today `templates\project\`; `gemeinsam`,
   `python`, `powershell`) with README, `CLAUDE.md`, `docs\architektur.md`,
   `docs\entscheidungen\`, `CHANGELOG.md`, `config\settings.json`, a first test, check command
   `scripts\Check.ps1` (steps in `config\check.json`) and git hook. `scripts\New-Project.ps1`
   creates a project from it, settings in `config\projects.json`, building blocks in
   `scripts\lib\Projects.ps1`.
5. **`scripts\Test-Templates.ps1`:** creates one project per language and checks placeholders,
   check command, first commit and that a built-in error makes check command and commit fail.
6. **Benchmark:** `-Overlay <name>` lays files from `benchmark\overlays\<name>\` into the working
   folder (here `projekt`, today `project`: `CLAUDE.md`, check command), `-Prefix <text>` puts a
   command in front of the task. `Test-Tasks.ps1 -Overlay projekt` checks the tasks with it.
7. **`Test-Setup.ps1`:** a new section for closing check and workflows.
8. **Documentation:** new [projects.md](projects.md); [agent.md](agent.md),
   [model-choice.md](model-choice.md), [roadmap.md](roadmap.md), [extending.md](extending.md),
   `architecture.md`, `README.md`, `CLAUDE.md`.

### Measured

`local-coder`, the five newer tasks three times each, llama.cpp b12359, Claude Code 2.1.325.

| | `stufe2` (before) | `stufe3` | `stufe3b` | `stufe3-projekt` |
|---|---|---|---|---|
| Passed | 9 / 15 | 11 / 15 | 12 / 15 | 11 / 15 |
| `psscript` | 0 / 3 | 3 / 3 | 3 / 3 | 3 / 3 |
| `longcontext` | 0 / 3 | 0 / 3 | 0 / 3 | 0 / 3 |
| `readme` | 7 / 15 | 14 / 15 | 13 / 15 | 12 / 15 |
| `tests` | 6 / 15 | 7 / 15 | 13 / 15 | 13 / 15 |
| `config` | 0 / 6 | 0 / 6 | 0 / 6 | 5 / 6 |
| Rules followed | 65 % | 77 % | 85 % | 91 % |
| Time | 3970 s | 5494 s | 5951 s | 6555 s |

`stufe3`: notes, closing check with the first reminder, workflows loaded. `stufe3b`: reminder
sharpened. `stufe3-projekt`: plus `CLAUDE.md` and check command in the working folder. Run
`stufe3-befehl` (`extend` three times with `/lokal:feature`): 2 / 3 in 914 s, rules 15 / 15.
Assessment: [model-choice.md](model-choice.md).

`Test-Setup.ps1`, `Test-Tasks.ps1`, `Test-Templates.ps1` passed, `Test-Guard.ps1` 89 of 89 cases.

### Errors and findings

- **The first reminder was too soft.** Asked "test written and run?", the model wrote a check
  script, ran it and deleted it again. The rule `tests` only rose when the reminder explicitly
  excluded that (7 to 13 of 15).
- **`config` needs a place, not a rule.** `DEFAULT_WAREHOUSE = "main"` stayed in the code despite
  rule and reminder, until a `CLAUDE.md` said where settings live.
- **`ExitCode` empty under PowerShell 5.1.** After `Start-Process -PassThru` and `WaitForExit`
  `ExitCode` was empty, and the hook took a passed check command for failed. Remedy: read
  `$null = $process.Handle` before waiting.
- **Workflows carry the name of the plugin.** `/bugfix` is not recognised in `claude-local -p`,
  `/lokal:bugfix` is.
- **No global git identity on this computer.** The first commit of a new project failed;
  `New-Project.ps1` now takes name and address from this repository when the new one has none.
- **More rounds fill the context.** With the project template `psscript` took 842 to 900 s
  instead of 507 to 572 s; one run reached the time limit, one ended with `blocking_limit`.

### Open

- Workflows and closing check in a real session at the terminal (so far only `-p`).
- `/lokal:bugfix`, `/lokal:pruefen` and decision files are not measured (N8).
- Linter, search for secrets and check of the dependencies in the check command (N9, S7).
- Make the closing check cheaper (Q9); `longcontext` needs more context (E2).
- `local-fast` and `local-qwen38` are not measured with the new way of working.

## 2026-11-15 afternoon: measurability (stage 2 of the roadmap)

### Reason

The user released stage 2: tasks that resemble real use (Q1), and a number for whether the model
follows the working rules (Q2).

### Done

1. **Five new tasks** in `benchmark\tasks\`: `extend`, `refactor`, `psscript`, `screenshot`,
   `longcontext` (description: [extending.md](extending.md)). Each has a reference solution in
   `solution\`.
2. **Rule adherence:** `benchmark\lib\rulecheck.py` with building blocks for six rules
   (`readme`, `tests`, `config`, `docstrings`, `headers`, `nodeadcode`). The check of a task
   prints them as a line `RULES {...}`; passing or failing does not depend on it.
3. **`scripts\Test-Tasks.ps1`:** checks without a model that every template fails and every
   reference solution passes, with all rules followed. Shared building blocks in
   `scripts\lib\Tasks.ps1` (`New-TaskWorkCopy`, `Invoke-TaskCheck`), which the benchmark uses as
   well.
4. **`scripts\Benchmark-Models.ps1`:** allowed commands and time limit per task from
   `config\benchmark.json` (`allowedTools`, `taskTimeoutSeconds`), output tokens and rules per
   run in `results.jsonl`, in the report the column "rules followed" and the section "working
   rules".
5. **Documentation:** [extending.md](extending.md) (tasks, rules, creating a new task),
   [model-choice.md](model-choice.md) (assessment), [roadmap.md](roadmap.md) (Q1 and Q2 struck
   out, starting point, new Q8), `architecture.md`, `README.md`, `CLAUDE.md`.

### Measured

Run `stufe2`, every task three times, llama.cpp b12359, Claude Code 2.1.325.

| Task | `local-coder` | `local-fast` |
|---|---|---|
| `extend` | 3 / 3 | 1 / 3 |
| `refactor` | 3 / 3 | 2 / 3 |
| `screenshot` | 3 / 3 | 0 / 3 |
| `psscript` | 0 / 3 | 0 / 3 |
| `longcontext` | 0 / 3 | 0 / 3 |
| Sum | 9 / 15 in 3970 s | 3 / 15 in 3679 s |
| Rules followed | 43 / 66 (65 %) | 34 / 66 (52 %) |

Raw values: `local-coder` load 9.3 s, 63.3 tok/s, reading 1321 tok/s, 14718 and 7529 MiB;
`local-fast` load 17.1 s, 129.1 tok/s, reading 3497 tok/s, 15108 and 9311 MiB. Times per run and
rate per rule: [model-choice.md](model-choice.md), [benchmark.md](benchmark.md).

The goal of Q1 (at least two new tasks that `local-coder` does not pass every time) is reached,
as is that of Q2 (rate per model in the report). `Test-Tasks.ps1`: all nine tasks in order.
`Test-Setup.ps1`: all checks passed. After the runs the GPU memory was free (7 and 0 MiB).

### Errors and findings

- **Three errors in our own checks.** The self-test found two before the first model run: the
  check of `refactor` required a particular order of the keys and then failed on Windows line
  endings; and Python used outdated `__pycache__` files of the template in a fresh working copy
  (same size, same second), so the reference solution of `longcontext` appeared wrong.
  `New-TaskWorkCopy` now removes these folders. Only the measurement found the third: the
  reference solution for Ireland contradicted the list of changes (a parcel too heavy with free
  shipping). The run concerned (`local-coder`, `longcontext` no. 2) also failed on Italy; its
  verdict does not change, but the saved check text wrongly names Ireland.
- **"Autocompact is thrashing".** In `longcontext` Claude Code itself ended four of six runs
  (`terminal_reason: rapid_refill_breaker`): the context was full again three times in a row
  within three rounds after compacting. Almost nothing was changed in these runs.
- **PowerShell 5.1:** six runs, six different mistakes, all on peculiarities of the shell
  (stderr, exit code, list with one entry, unwanted output).
- **`local-fast` reports success where there is none.** In `screenshot` it reported in every run
  that both calls from the picture worked now. Twice it had reproduced the first without
  `0.5h`, once it left `0.5h` aside as undocumented.
- **Refused calls in the benchmark.** Without a user at the terminal everything not allowed
  counts as refused. Affected were calls with `cd ... &&` before the command, write attempts to
  `/tmp` and a path with wrong upper and lower case (`E:\LlamaCPP`). No run demonstrably failed
  on that alone.
- **The rules work unevenly:** descriptions and "no dead code" almost always, README and tests
  in less than half of the runs, the value in the configuration file never.

### Open

- `local-qwen38` is not measured on the new tasks.
- The rule check is mechanical: it sees whether something happened, not how well.
- Three runs per task are few; for comparisons in stages 3 and 4 repeat the same tasks with the
  same procedure.
- Whether the working rules achieve anything at all only shows in a run without
  `entwicklungsregeln.md` (today `coding-rules.md`, P5).
- Stage 3 (way of working) waits for the user's release.

## 2026-11-15 morning: safety net (stage 1 of the roadmap)

### Reason

The user released stage 1 of the roadmap, with the condition: the protection should protect him,
not others, and not restrict the model in its work. From that the principle in
[security.md](security.md) and in `CLAUDE.md`: protected are your own computer and your own
data; no rules about content; normal work in the project folder stays free; when in doubt, a
question instead of a block.

### Done

1. **Key for the server (S1):** `requireApiKey` and `corsOrigins` in `config\server.json`. The
   key is created at the first start in `<installRoot>\run\api-key.txt` and reaches the server
   through the variable `LLAMA_API_KEY`. `Invoke-ServerApi`, `claude-local` and
   `Install-Continue.ps1` send it along; `config\continue.config.yaml` only contains a
   placeholder.
2. **Guard before every tool call (S2, S3):** `scripts\hooks\Guard-Tool.ps1` as a `PreToolUse`
   hook, rules in `config\guard.json`, hooked in through the settings file that `claude-local`
   creates for every launch (`lib\Safety.ps1`). Three blocks (deleting drives and system
   folders, formatting, boot configuration and backups), otherwise questions (deleting outside
   the project, git commands that throw work away, downloading and running, registry,
   antivirus, autostart, credentials).
3. **Git note at start (S4):** `gitCheck` in `config\agent.json`.
4. **`scripts\Test-Setup.ps1` (P1)** and **`scripts\Test-Guard.ps1`** with 89 cases in
   `tests\guard-cases.json`.
5. **Recording versions (P2):** `Test-Model.ps1` and the benchmark name the version of Claude
   Code (currently 2.1.325).
6. **Continue:** configuration with the key installed anew (old file backed up as
   `config.yaml.bak-20261115-083931`).
7. **Roadmap updated:** finished points struck out, S7 adapted to the principle (no question
   at every package installation), new S8 and S9.

### Measured

- **Key:** without a key server and model process answer with 401, with a key normally;
  `/health` stays open. The warning `no API key is set and CORS allows all origins` no longer
  appears in the server log. `Test-Model.ps1` with the key: `local-coder` 59.4 tok/s, tool call
  and image fine.
- **Model processes:** with `--api-key-file` at the router alone the model processes on their
  own ports keep accepting requests without a key; an entry in the model list is not passed
  on. Only the variable `LLAMA_API_KEY` works on both.
- **Guard:** 89 of 89 cases as expected, among them 32 normal working steps that stay free. A
  call costs 266 ms (mean of five).
- **In real sessions (`claude-local -p`):** creating a file, starting it with Python and
  `rm -rf __pycache__` run undisturbed (13 s). `format Q: /?` was blocked three times.
  `git reset --hard` and reading a file `tresor.kdbx` were not run; the model got the reason of
  the guard. All four decisions are in `<installRoot>\logs\guard.log`.
- **Broken `guard.json`:** the guard answers with a question (`guard-error`), not by letting the
  call through.
- **`Test-Setup.ps1`** reports an invalid JSON file, a script with a non-ASCII letter and a
  script with a lost comment sign, each with exit code 1.

### Errors and findings

- **The model gets round a block on its own.** After the third refusal of `format Q: /?` it
  called up the help another way. Harmless here, but it shows the limit of a guard that
  recognises commands by how they are written (roadmap S9, S6).
- **A test case was badly chosen:** `rm -rf ../guard-test-dummy` went through, because the test
  folder was in the temp folder, where deleting is free. The behaviour is intended.
- **Twice the `#` got lost when inserting a comment** (`Config.ps1`, `Server.ps1`); PowerShell
  only reported an error when the function was called. `Test-Setup.ps1` now checks for it.

### Open

- **Question in a session at the terminal** not seen myself: only runs without a user are
  checked, in which a question counts as no (roadmap S8).
- **Continue with the key** not tried in VS Code. The autocomplete entry sends the key twice
  (as `apiKey` and as a header), because it is not checked which way the provider `llama.cpp`
  of Continue takes.
- **The rule for the model "commit before larger rebuilds"** from the plan is not included in
  `entwicklungsregeln.md`: its effect on the benchmark tasks is not measured (catch up with Q2).
- The guard rules are checked on 89 imagined cases, not on weeks of real work.

## 2026-11-15: images, GPU memory after the session, roadmap

### Reason

The user reported: the local model still does not recognise images, and after `exit` the GPU
memory stays in use. Plus the wish for a roadmap.

### Done

1. **Image encoders entered** (from the evening before, not committed so far): `mmproj` in the
   three agent profiles, `Get-ModelProfile` resolves the file name, `Start-Server` loads a model
   without image input when the file is missing. `Test-Model.ps1` has the new line
   `image input`.
2. **Real cause of the image error fixed:** when a tool result comes together with text in one
   message, `llama-server` puts the text before the result. The built-in template of Qwen 3.6
   then stops with error 500. New: `config\templates\qwen3.6-agent.jinja` for `local-coder` and
   `local-fast`; the same block in `qwen3.8-agent.jinja`. Description in [models.md](models.md),
   section "Chat template".
3. **Small images are scaled up:** `image-min-tokens = 256` in the three profiles.
4. **GPU memory is freed when the last session ends:** `onExit` in `config\agent.json`
   (`unload`, `stop`, `keep`), switch `-OnExit` for one call, new building block
   `scripts\lib\Session.ps1`, `Stop-Models` in `lib\Server.ps1`. The benchmark calls
   `claude-local` with `-OnExit keep`. Description in [agent.md](agent.md).
5. **Idle limit:** `sleep-idle-seconds = 1800` for all profiles, as a safety net for closed
   windows and crashes ([backend.md](backend.md)).
6. **Roadmap:** [roadmap.md](roadmap.md).

### Measured

- **Error pattern:** the server log of the session of the evening before shows
  `A tool message must follow an assistant or tool message` five times (Claude Code repeats the
  request). Reproduced with direct requests to `/v1/messages`: tool result plus text always
  fails, with and without an image; a tool result alone works. The test of the evening before
  only sent the second form and therefore reported `OK`. It now sends the first.
- **After the fix:** 17 forms of messages (image alone, with text, two tools, two images, a
  pasted image, a system message in between) are all accepted.
- **Reading accuracy** with `local-coder`: 12 small images with a number, without
  `image-min-tokens` 5 right, with 256 and with 1024 all 12. 8 screenshots of a terminal right
  in every setting.
- **`Test-Model.ps1`** with the final configuration: `local-coder` 65.1 tok/s, `local-fast`
  136.7, `local-qwen38` 54.3; tool call and image fine for all.
- **The whole way:** `claude-local -p` with the task of reading a number from an image file
  answers correctly. Afterwards `claude-local` reports
  `models unloaded, GPU memory used now (MiB): RTX 5070 Ti 7, RTX 3060 0` (before 14268 and
  7633).
- **Two sessions:** while a second one runs, the model stays loaded; after its end the last
  one cleans up. The mark of an ended process is deleted.
- **Idle limit** (trial with 15 s): 14718 and 7529 MiB drop to 226 and 105 MiB, the next
  request answers after 7.2 s.
- The server without a loaded model takes no GPU memory.

### Errors and findings

- **A test that only checks the simple form proves little.** The image test passed the evening
  before, the real session failed. What counts is what Claude Code really sends; recorded with
  an intermediate server.
- **The error did not only affect images,** but every tool result with text attached, so above
  all interactive sessions. The runs of the benchmark (`-p`) did not hit it.
- **The conversion in llama.cpp is like that in the current state too** (`server-chat.cpp`,
  compared with `master`). An update does not fix it.
- **`models.json` was briefly invalid** (one backslash too few), the server did not start.
  Hence point P1 in the roadmap.
- During the work a second session worked on the look in the same repository; the changes to
  `claude-local.ps1` and `_common.ps1` were coordinated.

### Open

- **Source of the three `mmproj` files** is not recorded, checksums not checked (roadmap S5).
- **Pasting an image with Alt+V** in an interactive session not tried myself; checked are the
  same form of message through the interface and the way through `Read`.
- **Ending with a closed window** does not clean up; then the idle limit takes over.
- The effect of `sleep-idle-seconds` on long thinking pauses in a session (reading the context
  in again) is not measured.
- All points of the roadmap.

## 2026-11-14 night: the look "Nachtschicht" (today "Night Shift")

### Done

1. **One look for shell, `claude` and `claude-local`:** three moods of light whose colour
   temperature shows where the model runs (Werkbank = shell, Glut = local model, Fernlicht =
   cloud; today Workbench, Ember, High Beam). All colours, signs and texts in
   `config\style.json`, description in [style.md](style.md).
2. **New scripts:** `Install-Style.ps1` (applies, `-Remove` takes back, `-PreviewDir` only
   shows), `Install-Font.ps1` (IBM Plex Mono for the user), `style\Shell.ps1` (prompt, greeting
   with both graphics cards), `style\Statusline.ps1` (status line of Claude Code), building
   blocks in `lib\Style.ps1`.
3. **`claude-local`** tints the window warm for the duration of the session, hands over theme
   and status line for that launch and reports in ember colours. With redirected output the
   previous text lines stay, so the benchmark sees the same as before.
4. **Changed outside the repository** (each with a one-off backup `<name>.vor-nachtschicht`):
   `settings.json` of Windows Terminal (scheme, theme, profile "Nachtschicht" as the default)
   and `%USERPROFILE%\.claude\settings.json` (`theme`, `statusLine`, `spinnerVerbs`). New: two
   files in `%USERPROFILE%\.claude\themes\`, 16 font files in
   `%LOCALAPPDATA%\Microsoft\Windows\Fonts`, `%LOCALAPPDATA%\Nachtschicht\glut.png`. The
   execution policy of the system and the PowerShell profile are unchanged.

### Measured

Start of the shell with greeting about 440 ms (PowerShell alone 134 ms), one prompt about 30 ms,
one run of the status line about 380 ms. A second run of `Install-Style.ps1` no longer changes
the files.

### Open

- **Not checked on screen.** It was set up without a look at the window. To be confirmed:
  colour effect, typeface, whether the window changes its mood at the start of `claude` and
  `claude-local` and returns afterwards, whether Claude Code accepts the themes without a
  message.
- `claude-local` with the new look is only partly checked (start message, settings file,
  control sequences), not as a whole session: the server was busy with parallel work.

## 2026-11-14 evening: Ollama removed, loop explained, new models

### Done

1. **Ollama uninstalled:** program, its model folder (64 GB), `%USERPROFILE%\.ollama`, the
   autostart entry and the user variables `OLLAMA_*` and `LLAMA_ARG_TENSOR_SPLIT` are removed.
   The models in the model folder of llama.cpp were kept (hard links).
2. **Autostart checked:** there is no entry for `llama-server` under `Run`, in the autostart
   folder, as a service or as a scheduled task. Nothing to change.
3. **Loop of qwen3-coder 30B explained:** a started `<tool_call>` at the end of the answer,
   llama.cpp forces a call out of it. Explanation in [model-choice.md](model-choice.md).
4. **Lean tool set:** `claude-local` only allows `Bash, Read, Edit, Write, Glob, Grep` and
   switches off auto memory and bundled skills (`tools` and `env` in `config\agent.json`,
   [agent.md](agent.md)).
5. **New benchmark task `planner`**, harder than the previous ones. Time limit per run 600
   instead of 420 s. `Benchmark-Models.ps1` has the new switch `-Tasks`.
6. **Three candidates measured:** Qwen 3.6 27B Heretic v2 and Qwen 3.6 35B-A3B Heretic
   (downloaded from Hugging Face, checksums checked) and gpt-oss 20B (already on the disk for
   another project, hooked in as a hard link).
7. **Profiles switched:** `local-coder` = Qwen 3.6 27B, `local-fast` = Qwen 3.6 35B-A3B, new
   `local-qwen38` = the previous default model. Profiles for qwen3-coder 30B and gpt-oss 20B
   removed, the files not. `/model` shows three entries. Continue installed anew (old file
   backed up as `config.yaml.bak-20261114-205326`).
8. **Measurement data renamed:** in `logs\benchmark\results.jsonl` the llama.cpp entries carry
   the new profile names, so that the report fits the configuration (mapping in
   [model-choice.md](model-choice.md)).

### Measured

Table and assessment in [model-choice.md](model-choice.md). In short: Qwen 3.6 27B passed all 6
runs of `planner` in 135 to 189 s, Qwen 3.8 27B 5 of 6 in 216 to 600 s, Qwen 3.6 35B-A3B and
gpt-oss 20B 1 of 3 each. All four pass the easy tasks.

`Test-Model.ps1` after the switch: `local-coder` 60.5 tok/s, `local-fast` 140.8 tok/s,
`local-qwen38` 51.8 tok/s, tool call fine for all.

### Open

- **A file without a profile** in the model folder: `gpt-oss-20b-MXFP4.gguf` (hard link, no
  space of its own). `qwen3-coder-30b-Q4_K_M.gguf` (18.6 GB) was deleted at the user's request
  the same evening.
- **Refusal rate** of the new models not checked ourselves.
- **One pass at 37 instead of 60 tok/s** with Qwen 3.6 27B right after a restart of the server,
  cause not checked.
- Still unchecked: `/model` in an interactive session, Continue in VS Code.

## 2026-11-14 afternoon: switch from Ollama to llama.cpp, working rules

### Done

1. **llama.cpp installed:** build b12359 (CUDA 13.5) into `<installRoot>\b12359`, checksums
   checked against GitHub. Script: `scripts\Install-LlamaCpp.ps1`.
2. **Models taken over:** the three GGUF files from the Ollama stock laid into the model folder
   as hard links (`scripts\Add-Model.ps1`). Nothing downloaded anew, nothing deleted.
3. **Server in router mode:** one `llama-server` on `127.0.0.1:8080` that loads and unloads
   models when needed. Settings in `config\server.json`, profiles in `config\models.json`.
4. **GPU split per model:** `local-coder` 70:30, `local-fast` 65:35, autocomplete alone on the
   3060.
5. **Chat template adapted:** `config\templates\qwen3.8-agent.jinja`, see below.
6. **`claude-local` switched:** connection to the new server, context size from `models.json`,
   model choice for `/model` taken over.
7. **Working rules for the local model:** `config\entwicklungsregeln.md` (544 tokens; today
   `coding-rules.md`) is appended to every session. Both models repeat the rules correctly when
   asked.
8. **Scripts reorganised:** shared building blocks in `scripts\lib\` (`Config.ps1`,
   `Server.ps1`, `Measure.ps1`). New: `Start-`, `Stop-`, `Restart-Server.ps1`. `Test-Model.ps1`
   and `Benchmark-Models.ps1` ported to llama.cpp. The Ollama scripts, `modelfiles\` and
   `config\ollama.env.json` removed (git history up to `fbb8c80`).
9. **Continue switched:** `config\continue.config.yaml` points to the new server.
10. **New documentation:** README, `architecture.md`, `setup.md`, `extending.md`; new
    `backend.md`, `models.md`, `agent.md` and `CLAUDE.md` with the rules for this project.

### Measured

Run `llamacpp`, every task three times ([model-choice.md](model-choice.md)):

| Profile | Passed | Time | Before through Ollama |
|---|---|---|---|
| `local-coder` | 9 / 9 | 431 s | 9 / 9 in 993 s |
| `local-fast` | 7 / 9 | 1709 s | 3 / 3 in 172 s (one run per task) |

The comparison for `local-coder` is not clean: backend, GPU split, chat template and working
rules changed at the same time.

Interfaces for Continue checked with direct requests: chat through `/v1/chat/completions`
(streaming) and completion through `/completion` (183 tok/s). `local-coder` and the autocomplete
model are loaded at the same time (13.5 and 8.9 GB in use).

### Errors and findings

- **The chat template of Qwen 3.8 refuses later system messages**
  (`System message must be at the beginning.`). Claude Code sends such messages in the middle
  of the conversation, every request ended with error 500. Ollama gets round that with a
  renderer of its own. Solution: an own template with one changed place.
- **`LLAMA_ARG_TENSOR_SPLIT` from the Ollama days** is in the user environment and is read by
  every `llama-server`. `Start-Server` removes `LLAMA_ARG_*` before the start.
- **A benchmark working folder inside the repository distorts the tasks:** Claude Code loads
  the `CLAUDE.md` of all parent folders. After the `CLAUDE.md` was created, `local-fast` looked
  for the task files in the project folder (3 of 9 runs failed). The working folder is now in
  `<installRoot>\bench-work` (`workDir` in `config\benchmark.json`), the run was repeated.
- **`timeout` in Git Bash does not end Claude Code with it.** Test runs started by hand kept
  running after the break-off and occupied the model. Consequence: `model limit reached` when
  switching, because the server does not unload a model in use. An attempt with a second chat
  template for `local-fast` cannot be evaluated because of that and was dropped. The benchmark
  script is not affected (`taskkill /T`).
- **Ollama models created locally** (`ollama create`) are not in the old manifest folder.
  `Add-Model.ps1 -FromOllama` only finds downloaded models; for the others give the blob with
  `-Path`.

### Open

- **`local-fast` keeps going through llama.cpp after the solution** (calls `ReportFindings`,
  memory notes, `Skill`, up to 56 rounds). Not through Ollama on the same day (one run). Cause
  unclear.
- **Continue in VS Code not checked.** The new configuration is installed
  (`Install-Continue.ps1`, old file backed up as `config.yaml.bak-20261114-172513`), but the
  operation in VS Code not tried. The server does not start with Windows by itself; for
  Continue run `Start-Server.ps1` or `claude-local` first.
- **`/model` in an interactive session** still unchecked, as are background requests after a
  switch.
- **Ollama is still installed** with its models (about 100 GB) and environment variables. It is
  no longer needed for this project; it is only removed at the user's explicit wish.
- Measure the effect of GPU split, working rules, thinking effort and MTP length one by one.
- Harder benchmark tasks.
- Refusal rates still only according to the model cards.

## 2026-11-14: repeated measurement of the uncensored models

### Done

`Benchmark-Models.ps1 -Only "unc-*" -Label repeat3 -Repeat 3`: `unc-heretic`, `unc-blackfrost`
and `unc-coletti` at 64k context, every agent task three times.

### Result

- All three models passed 9 of 9 runs, no run exceeded the time limit.
- Time per pass: `unc-heretic` 350 / 334 / 309 s, `unc-coletti` 363 / 263 / 389 s,
  `unc-blackfrost` 706 / 638 / 331 s.
- The ranking of Nov 13 (Blackfrost fastest, Heretic slowest) was not confirmed. The spread
  between the runs is larger than the gap between the models. Evaluation:
  [model-choice.md](model-choice.md), section "Repeated measurement".

### Switch and cleanup

- `local-coder` is now based on `unc-heretic` (`modelfiles\local-coder.Modelfile`, rebuilt).
  `Test-Model.ps1`: 54.9 tok/s, tool call fine, 100 % GPU.
- Deleted: `unc-blackfrost`, `unc-coletti`, `local-legacy` with the base model
  `mgraffam/qwen3.8-EfficientThink-uncensored:27b` and the three GGUF files in the import
  folder of Ollama. That freed 97 GB on the drive (179 → 276 GB free).
- Profile `local-legacy` and short name `alt` removed. The deleted models are still in
  `config\benchmark.json`; the benchmark script skips models that are not installed.

### Switching the model in the session (`/model`)

- `claude-local` hands Claude Code the setting `modelPicker` through a file for that launch only
  (`--settings`, file `%TEMP%\claude-local-settings.json`). So the choice of `/model` shows the
  profiles from `picker` in `config\agent.json` instead of the Anthropic models. The normal
  command `claude` is not affected.
- `CLAUDE_CODE_SUBAGENT_MODEL` is no longer set, so that subagents follow the main model after
  a switch.
- The context window applies to the whole session; with several models the smallest counts.
- Checked: start with both models through `-p`, the generated settings file. Not checked: the
  choice itself in an interactive session.
- Open: background requests ("haiku") still go to the starting model. In a run with `-p` there
  were none; whether an interactive session sends some after the switch and Ollama then
  reloads is not measured.

### Open

- Refusal rates still only according to the model cards, not checked ourselves.
- The context length in the Ollama app is still 262144 (only affects models without a
  profile).
- Optional: GPU split depending on the model (70:30 for MTP models).

## 2026-11-13 night: GPU split, uncensored models with MTP, GitHub

### Done

1. **Switching models:** profile `local-fast` (`qwen3-coder:30b`), short names in
   `config\agent.json` (`claude-local -Model schnell|unzensiert|alt`), both chat models in
   Continue.
2. **Privacy:** in VS Code `continue.telemetryEnabled` and `continue.enableNextEdit` off, in
   Ollama `OLLAMA_NO_CLOUD=1`.
3. **GPU split measured** (`scripts\Measure-GpuSetups.ps1`, 14 setups). Result: the PCIe 4.0 x4
   of the 3060 does not slow things down when splitting by layers, the 3060 itself does.
   `LLAMA_ARG_TENSOR_SPLIT=65,35` set. Details: [gpu-tuning.md](gpu-tuning.md).
4. **MTP discovered:** the official `qwen3.8:27b` is twice as fast with MTP. The previous
   uncensored model lacks the MTP layers. Three uncensored variants with MTP downloaded from
   Hugging Face (into the import folder of Ollama), imported with `scripts\Import-Gguf.ps1`, all
   passed the benchmark with 3 / 3.
5. **Default model changed:** `local-coder` is now based on `unc-blackfrost`, about 55 instead
   of 25 tok/s. The old model stays as `local-legacy`. End-to-end test with `claude-local`: file
   created correctly and run, MTP active.
6. **Git:** repository created and pushed to GitHub (private: `MD220411/Unzensiert`).

### Errors and findings

- **The measuring script hung for two hours.** `ConvertTo-Json` in Windows PowerShell 5.1
  serialised hidden properties of `Get-Content` lines (PSProvider) and did not come to an end.
  Fixed with a `[string]` conversion.
- **The measuring script lost `num_ctx`.** For a hashtable the helper function read its
  properties instead of its entries. Ollama therefore loaded `qwen3.8:27b` with the 262k context
  of the app, partly on the CPU, at 14 instead of 60 tok/s. Fixed, affected values measured
  again. The script now detects reloads.
- **Ollama reports "100 % GPU" even when layers are in main memory.**
- **`CUDA_VISIBLE_DEVICES` alone does not hide a card:** Ollama then finds it through Vulkan.
  For single-card tests also `OLLAMA_VULKAN=0`.
- **The first download broke off** (the connection hung for 30 minutes). The download script
  breaks off on a standstill and resumes.

### Open

- The GGUF files in the import folder of Ollama (51 GB) exist twice after the import and can
  be deleted. Likewise `unc-heretic`, `unc-coletti` and `local-legacy` with the base model, if
  no longer needed (17 to 19 GB each).
- The context length in the Ollama app is still 262144 (only affects models without a
  profile).
- Refusal rates of the uncensored models only according to the model cards, not checked
  ourselves.
- Repeated measurement (`-Repeat 3`) for a solid ranking of the uncensored models.

## 2026-11-13 evening: phase 5 finished, benchmark evaluated

### Autocomplete checked

`Restart-Ollama.ps1` and `Install-Continue.ps1` run, `qwen2.5-coder:1.5b-base` downloaded
(capabilities according to Ollama: `completion, insert`). Test with the same request Continue
sends:

| Check | Result |
|---|---|
| `local-coder` loaded first, then autocomplete | both 100 % GPU |
| autocomplete loaded first, then `local-coder` | both 100 % GPU |
| VRAM in use | 5070 Ti 13.4 of 16.3 GB, 3060 10.5 of 12.3 GB |
| response time FIM (warm) | 0.15 s |
| result | `is_prime` completed correctly |

`Install-Continue.ps1` now downloads the model through the API instead of `ollama pull`,
because the progress bars filled the output with control characters.

### Benchmark

Run 15:25 to 17:12, all 12 combinations measured. Assessment in
[model-choice.md](model-choice.md). The core: only three models solve all tasks, all three only
with 64k. `qwen3-coder:30b` is three times as fast as `local-coder`. Every task ran only once,
a repeated measurement is still open.

## 2026-11-13 afternoon: phase 5, autocomplete

### Done

1. VS Code extension Continue 2.0.0 installed. Compared with llama.vscode and Twinny: Continue
   chosen because it offers a chat with `local-coder` next to autocomplete.
2. `config\continue.config.yaml` created: chat with `local-coder`, autocomplete with
   `qwen2.5-coder:1.5b-base`. This base variant is trained for filling in the middle (FIM).
   Copied to `%USERPROFILE%\.continue\config.yaml` with `scripts\Install-Continue.ps1`.
3. `OLLAMA_MAX_LOADED_MODELS` set from 1 to 2 (user environment). Only effective after
   `Restart-Ollama.ps1`, which is still pending because of the running benchmark.

### Findings from the source code of Continue 2.0.0

- Continue reads `num_ctx` from the Ollama profile through `/api/show`, as long as the
  configuration has no `contextLength`. So for `local-coder` it sends 65536. A different value
  would make Ollama reload the model at every switch between `claude-local` and Continue. Models
  without `num_ctx` get 8192 from Continue.
- For FIM Continue sends the text before and after the cursor as `prompt` and `suffix` to
  `/api/generate`. The template of the Ollama model builds the FIM prompt from it. So an own
  profile is not needed for the autocomplete model.
- Continue itself sets `keep_alive` to 30 minutes.

## 2026-11-13 afternoon: comparing models

### Done

1. `scripts\Benchmark-Models.ps1` built: raw values (load, speed, tool calls, thinking) and three
   agent tasks through `claude-local` (`benchmark\tasks\`: bugfix, feature, multifile).
2. First run 14:23–14:48: `qwen38-unc-64k` complete (3 / 3 passed). For `qwen38-unc-32k` the run
   was broken off during the third task because the session ended.
3. Run continued from 15:25, output in `logs\benchmark\run-20261113-1525.log`. `flint:40b` is
   not installed and is skipped.
4. The old stock `%USERPROFILE%\.ollama\models` is deleted, `C:` has 185.4 GB free.

### Errors and findings

- **32k context is hardly enough for Claude Code.** With `qwen38-unc-32k` Claude Code reported
  "Autocompact is thrashing" in the bugfix task: the context filled up again within three
  rounds. The run took 415 s with a limit of 420 s, the feature task ran into the time limit.
  System prompt and tool descriptions of Claude Code alone take a large part.
- **The report counted runs over the time limit as passed** when the files happened to be right
  already. Fixed: such runs now count as failed and appear as `time, files ok`.

## 2026-11-13: phases 1 to 3 (backend, model, agent)

### Starting point

- RTX 5070 Ti (16 GB) and RTX 3060 (12 GB), i9-14900K, 128 GB RAM
- Ollama 0.40.9, four models, model folder according to the app setting `%USERPROFILE%`
- `C:` with 56.7 GB free

### Done

1. Project structure created (`config`, `modelfiles`, `scripts`, `bin`, `docs`).
2. Environment variables set from `config\ollama.env.json`.
3. Ollama updated from 0.40.9 to 0.40.16 (signature of the installer checked).
4. Model stock (58.4 GB: `blobs`, `manifests`, `manifests-v2`) copied from `%USERPROFILE%` to
   another drive, checked file by file, source deleted afterwards. `C:` now has 112.7 GB free.
5. Model folder in the settings of the Ollama app set to the new place. Backup of the app
   database: `%LOCALAPPDATA%\Ollama\backup-20261113-140928\`.
6. Profile `local-coder` built and measured.
7. Starter `claude-local` created, `bin\` added to the user PATH.

### Measurements `local-coder`

| Context | VRAM total | Placement | Speed | Tool calls |
|---|---|---|---|---|
| 32768 | 21 GB | 100 % GPU | 23.8 tokens/s | OK |
| 65536 | 22 GB | 100 % GPU | 24.2 tokens/s | OK |

At 64k about 0.6 GB are free on the 5070 Ti and about 3 GB on the 3060. Chosen: 64k.

### End-to-end tests with `claude-local`

| Task | Result | Duration |
|---|---|---|
| create the file `fizzbuzz.py` | correct, runs | 26 s |
| read a file, change it, run it with Python, report the output | correct | 36 s |

### Errors and findings

- **The wrong folder copied.** At first the default folder `%USERPROFILE%\.ollama\models`
  (71.7 GB) was copied. It was an old stock. The real stock lay directly in `%USERPROFILE%`
  because of the app setting. The wrong copy was deleted, the source stayed untouched.
  Consequence for the script: `Move-OllamaModels.ps1` now requires `-Source` explicitly and only
  touches `blobs` and `manifests*`.
- **The Ollama app overrides `OLLAMA_MODELS` and `OLLAMA_CONTEXT_LENGTH`.** Details were in the
  setup documentation of the time.
- **The base model brings `num_ctx 262144` along.** Hence the own profile.
- **`Start-Process -Wait` hangs with the Ollama installer**, because it also waits for the
  Ollama process the installer starts. Fixed in `Update-Ollama.ps1`.
- **Claude Code assumes 1 million tokens of context for unknown model names.** Fixed through
  `CLAUDE_CODE_MAX_CONTEXT_TOKENS` in the starter.
- **PowerShell binds flags like `-p` to its own parameters.** So the starter evaluates `$args`
  by hand.

### Open

- ~~Delete the old stock `%USERPROFILE%\.ollama\models` (71.7 GB).~~ Done, see above.
- The context length in the Ollama app is still 262144.
- Not tested yet: long sessions with compaction, large projects, behaviour with VRAM taken by
  other programs.
- Phase 4 (Roo Code or Cline as a fallback) was not needed.
- ~~Phase 5 (autocomplete with a small model).~~ Done, see above.

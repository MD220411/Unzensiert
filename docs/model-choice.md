# Model choice

Assessment of the measurements in [benchmark.md](benchmark.md). The latest measurement is in
the first section, the choice of models in the section "Current choice". The sections below
are older and stay as the reasoning.

## Agent: Unzensiert against Claude Code, all tasks three times (2026-11-18)

Run `vergleich2`: all eleven tasks, each three times, `local-coder`, without the second look,
otherwise like `vergleich1` (section below). This time `claude-local` ran first (06:40 to
08:30), then Unzensiert (08:30 to 10:03), so that a warm-up phase or the warmth of the cards
does not favour Unzensiert. Per task the median of time and rounds from three runs, plus the
runs passed. A run at the time limit counts as failed, as in [benchmark.md](benchmark.md),
even if its files pass the check:

| Task | Unzensiert | claude-local (Claude Code) |
|---|---|---|
| `bugfix` | 29 s, 8 rounds, 3 / 3 | 35 s, 11 rounds, 3 / 3 |
| `feature` | 67 s, 17 rounds, 3 / 3 | 80 s, 21 rounds, 3 / 3 |
| `multifile` | 81 s, 21 rounds, 3 / 3 | 96 s, 32 rounds, 3 / 3 |
| `planner` | 187 s, 27 rounds, 3 / 3 | 293 s, 53 rounds, 2 / 3 (once time limit, files right) |
| `extend` | 201 s, 23 rounds, **1 / 3** | 267 s, 37 rounds, 3 / 3 |
| `refactor` | 176 s, 31 rounds, 2 / 3 (once time limit, files right) | 258 s, 54 rounds, 3 / 3 |
| `psscript` | 306 s, 54 rounds, 3 / 3 | 425 s, 56 rounds, 3 / 3 |
| `screenshot` | 85 s, 13 rounds, 3 / 3 | 89 s, 20 rounds, 3 / 3 |
| `longcontext` | 299 s, 41 rounds, 1 / 3 | 366 s, 74 rounds, 2 / 3 |
| `datenblatt` | 110 s, 18 rounds, 2 / 3 | 135 s, 30 rounds, 1 / 3 |
| `pinwechsel` | 88 s, 15 rounds, 3 / 3 | 116 s, 30 rounds, 3 / 3 |
| **together** | **27 / 33 passed, 1,629 s, 268 rounds, 98,591 tokens, rules 88 / 96** | **29 / 33 passed**, 2,160 s, 418 rounds, 122,004 tokens, rules 86 / 96 |

"Together" means for time, rounds and tokens: the sum of the medians per task. Tokens are the
ones written by the model.

- **Speed:** Unzensiert was faster on all eleven tasks, 25 % less time, 36 % fewer rounds and
  19 % fewer tokens written altogether. Over all 66 runs 5,528 s against 6,541 s (15 % less,
  both with one time-out of 600 s). That confirms `vergleich1`, now with repetitions, all
  tasks and the reverse order.
- **Passed:** 27 against 29 of 33, counting the files of the runs at the time limit 28 against
  30. The difference is within the chance of this sample (Fisher's exact test, p = 0.73). All
  failures with a wrong result are mistakes of the model that also happen with Claude Code:
  - `extend`, twice with Unzensiert: `transfer` does not normalise the item name (`"Bolt"`
    instead of `"bolt"`). Exactly this mistake (`only 0 of Bolt in main`) hit Claude Code in
    2 of 28 runs so far. Unzensiert had checked the new behaviour with its own scripts and 24
    new tests, only not with a capitalised name.
  - `longcontext`: the same mistakes as in earlier runs with Claude Code (Spain without
    `invoice`, Ireland without upper limit). Over all runs so far Claude Code passed the task
    in 6 of 24 cases.
  - `datenblatt`: the same wrong value from the datasheet (HX-7) for both.
- **Time-outs:** one each, both solutions passed anyway. With Unzensiert (`refactor` #1) the
  model went in circles for six minutes: it wanted to repair its own new test, wrote the same
  file four times with the same content and tried 16 edits that changed nothing. The
  protection against repetition did not take hold, because every change to a file reset its
  counter, even a Write with the same content, and because the test output never looked the
  same due to the run time (`Ran 7 tests in 0.507s`, `0.493s`, `0.496s`, each time with the
  same `TypeError`). Fixed since ([unzensiert.md](unzensiert.md), "Built-in help against
  loops").
- **Rules:** 88 against 86 of 96, practically equal. Both missed `config` in `extend` and
  `psscript` in all runs; in addition Claude Code missed `tests` four times, Unzensiert
  `readme` and `tests` once.

Not measured: the second look (`-Git`); its reviewer `local-qwen38` would mean a model switch
with every task.

## Agent: Unzensiert against Claude Code (2026-11-17)

The same benchmark with both agents, `local-coder`, the same server, the same tools (`tools`
in `config\agent.json`), the same allowed commands, the same working rules and closing check,
run `vergleich1`, one run each, without the second look ([unzensiert.md](unzensiert.md)):

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
within the spread; that it goes in the same direction for all five speaks for a real
difference but does not prove it. Rounds are the requests to the model for Unzensiert, its own
figure `num_turns` for Claude Code. Not measured: `longcontext` (summarising with a full
context), `psscript`, the older tasks, repetitions (`-Repeat 3`) and the second look (`-Git`).

## Faithfulness to facts and consistency across files (2026-11-17)

Two new tasks after the classes of errors from real firmware work
([extending.md](extending.md)), `local-coder`, three times each, run `h4`:

| Task | Passed | Time for 3 runs | Rules | of which `fakten` (facts) |
|---|---|---|---|---|
| `datenblatt` (driver after the datasheet of a made-up sensor) | 3 / 3 | 448 s | 12 / 15, after correcting the rule check 15 / 15 | 3 / 3 |
| `pinwechsel` (move pins consistently in five places) | 3 / 3 | 338 s | 15 / 15 | 3 / 3 |

With datasheet and facts file in the project, `local-coder` looks things up instead of copying
from the predecessor and keeps pins consistent across all places. Whether that is due to facts
file and rule or to the manageable size of the tasks, the measurement does not separate. Runs
without the facts file and with the second look (`-Git`) for comparison are still open.
Details: [development log](devlog.md) of 2026-11-17.

## Fine-tuning: context, memory, closing check (2026-11-16)

Stage 4 of the [roadmap](roadmap.md), first part. Raw values from three to five measurements of
`local-coder` each, tasks as in the section below.

| Point | Measured | Decision |
|---|---|---|
| E1 image encoder on the RTX 3060 (`mmproj-device`) | 5070 Ti 13.6 instead of 14.8 GB, 3060 8.7 instead of 7.6 GB; image test 2.4 to 2.8 s as before; speed the same | stays, all three profiles |
| E2 context | 96k: 14.6 and 9.6 GB; 128k: 15.6 and 10.4 GB; speed the same (59 to 65 tok/s). 32k cost about 1.0 GB on the 5070 Ti and 0.85 GB on the 3060. With 128k `local-fast` (14.9 and 11.5 GB, 131 tok/s) and `local-qwen38` (15.3 and 10.2 GB, 55 tok/s) load as well | 128k for all three |
| G2 GPU split at 64k | 70/30: 61 tok/s, reading 1316; 73/27: 62.6 and 1448; 76/24: 64.5 and 1578; 79/21: 65.5 and 1635; 82/18 does not load | stays 70/30: the memory of the 5070 Ti goes to the context |
| G1 MTP length (`spec-draft-n-max`) | 2: 52.0 tok/s (80 % accepted); 3: 59.4 (72 %); 4: 61 to 62 (63 %); 6: 57.4 (50 %); 8: 50.5 (41 %) | stays 4 |
| Q5 larger quantisation (Q5_K_M) | loads with 64k at a split of 66/34 (14.4 and 10.1 GB): 54 tok/s, reading 1152; with 96k at 70/30 it does not load | profile `local-coder-q5` for comparison; quality not measured |

The five tasks three times each, `local-coder`:

| | `stufe3b` (64k) | `stufe4` (128k, encoder on the 3060, reminder only for open points) |
|---|---|---|
| `extend` | 3 / 3 (348, 377, 402 s) | 3 / 3 (334, 245, 241 s) |
| `refactor` | 3 / 3 (400, 290, 503 s) | 3 / 3 (264, 248, 244 s) |
| `psscript` | 3 / 3 (572, 553, 507 s) | 3 / 3 (446, 636, 566 s) |
| `screenshot` | 3 / 3 (128, 102, 135 s) | 3 / 3 (113, 138, 146 s) |
| `longcontext` | 0 / 3 (554, 363, 717 s) | 2 / 3 (494, 382, 406 s) |
| **Passed** | **12 / 15** in 5951 s | **14 / 15** in 4903 s |
| `readme` | 13 / 15 | 15 / 15 |
| `tests` | 13 / 15 | 15 / 15 |
| `config` | 0 / 6 | 0 / 6 |
| **Rules followed** | **56 / 66 (85 %)** | **59 / 66 (89 %)** |

Before that `longcontext` alone ran three times with 128k and the old reminder (run
`stufe4-128k`): 1 / 3 passed, the others with 1 and 2 wrong of 21 countries, all three ended
normally. The time of the second run (41474 s) is useless: the computer went to sleep during
it.

Assessment:

- **128k context solves the break-off of the long task.** In six runs with 128k every one
  ended normally, three passed; with 64k none of twelve passed, and several broke off at the
  full context. The mistakes that remain are single overlooked rules (Ireland: a parcel too
  heavy with free shipping).
- **The more economical reminder costs no rule adherence.** README and test in 15 of 15 runs,
  with 18 % less run time. How much of that is due to the reminder and how much to the context
  the measurement does not separate; `extend` and `refactor`, which do not fill the context,
  got 32 % faster (1576 instead of 2320 s).
- **`config` stays at 0 of 6 without the project template.** The `CLAUDE.md` does that
  (section below).
- **Limits:** three runs per task; two changes at once; `local-fast` and `local-qwen38` are
  only loaded with 128k and measured for speed, not on the tasks. Tab completion of Continue
  next to `local-coder` with 128k is not checked (about 1.8 GB are still free on the 3060).

## Way of working: notes, closing check, project template (2026-11-15 evening)

The same five tasks, only `local-coder`, three times each. The state of stage 2 is compared
with three extensions ([agent.md](agent.md), [projects.md](projects.md)):

| Run | What applies |
|---|---|
| `stufe2` | baseline: only the working rules |
| `stufe3` | plus notes on PowerShell 5.1, closing check with the first version of the reminder, workflows loaded |
| `stufe3b` | like `stufe3`, reminder sharpened (a deleted check script does not count as a test, constants belong in the configuration file) |
| `stufe3-projekt` | like `stufe3b`, plus a short `CLAUDE.md` and the check command `scripts\Check.ps1` in the working folder, as in a project from `New-Project.ps1` (`-Overlay project`) |

| | `stufe2` | `stufe3` | `stufe3b` | `stufe3-projekt` |
|---|---|---|---|---|
| `extend` | 3 / 3 | 2 / 3 | 3 / 3 | 3 / 3 |
| `refactor` | 3 / 3 | 3 / 3 | 3 / 3 | 3 / 3 |
| `screenshot` | 3 / 3 | 3 / 3 | 3 / 3 | 2 / 3 |
| `psscript` | 0 / 3 | 3 / 3 | 3 / 3 | 3 / 3 |
| `longcontext` | 0 / 3 | 0 / 3 | 0 / 3 | 0 / 3 |
| **Passed** | **9 / 15** | **11 / 15** | **12 / 15** | **11 / 15** |
| Time for 15 runs | 3970 s | 5494 s | 5951 s | 6555 s |
| `readme` | 7 / 15 | 14 / 15 | 13 / 15 | 12 / 15 |
| `tests` | 6 / 15 | 7 / 15 | 13 / 15 | 13 / 15 |
| `config` | 0 / 6 | 0 / 6 | 0 / 6 | 5 / 6 |
| `docstrings`, `headers`, `nodeadcode` | 30 / 30 | 30 / 30 | 30 / 30 | 30 / 30 |
| **Rules followed** | **43 / 66 (65 %)** | **51 / 66 (77 %)** | **56 / 66 (85 %)** | **60 / 66 (91 %)** |

Raw values in these runs: 58 to 61 tok/s.

Plus a small run `stufe3-befehl`: `extend` three times, task with `/lokal:feature` (today
`/local:feature`) in front, without the project template: 2 / 3 passed in 914 s, rules
15 / 15, among them `config` 3 / 3. For comparison `extend` in `stufe3b`: 3 / 3 in 1127 s,
rules 12 / 15, `config` 0 / 3.

Assessment:

- **The notes on PowerShell 5.1 work.** `psscript` passes in all nine runs since the notes,
  before that in none of six.
- **The closing check brings the README, only the sharpened version the tests as well.** After
  the first version the model checked the new logic with throwaway scripts and deleted them
  again; `tests` only rose from 6 to 7. Since the reminder says that explicitly, tests are in
  the project in 13 of 15 runs.
- **Only a concrete note brings the value into the configuration file.** General rule and
  reminder: 0 of 18. With a `CLAUDE.md` that says where settings are and who reads them: 5 of
  6. With the workflow `/feature`: 3 of 3.
- **The price is time.** 50 % more run time with the sharpened reminder, 65 % more with the
  project template. Most expensive is `psscript` with the project template: 842 to 900 s
  instead of 507 to 572 s; one run reached the time limit, one filled the context
  (`blocking_limit`). Both had solved the task by then.
- **`longcontext` stays at 0 of 12.** Of the six runs in `stufe3b` and `stufe3-projekt` three
  ended normally, with 1, 3 and 2 wrong of 21 countries; the other three broke off at the full
  context (`rapid_refill_breaker`, `blocking_limit`). The way of working does not solve that;
  it remains a question of context (E2 in the [roadmap](roadmap.md)).
- **The remaining failures are real mistakes of the model:** `extend` in `stufe3` and
  `stufe3-befehl` (rebooking fails in one of the checked cases), `screenshot` in
  `stufe3-projekt` (`0.5h` from the picture not handled).
- **Limits of the measurement:** three runs per task, one model. Differences of one run (11,
  12, 11 of 15) are chance. In `stufe3` notes, closing check and loaded workflows came in at
  the same time; their effect can only be separated through the tasks (`psscript` for the
  notes, `readme` and `tests` for the check). The rule check stays mechanical. `/feature` is
  only measured on one task, `/bugfix` and `/review` not at all. The `CLAUDE.md` of the
  measurement is written by hand for the tasks, after the pattern of the template.

## Harder tasks and working rules (2026-11-15)

Five new tasks that resemble real use ([extending.md](extending.md)), three times each, run
`stufe2`. The choice of 2026-11-14 (section "Current choice") stays and is now more broadly
supported.

| Task | `local-coder` | `local-fast` |
|---|---|---|
| `extend` (extend a project, the old must keep working) | 3 / 3 (251, 191, 171 s) | 1 / 3 (186, 189, 119 s) |
| `refactor` (refactoring across seven files) | 3 / 3 (319, 216, 187 s) | 2 / 3 (120 s, time limit 600 s, 98 s) |
| `screenshot` (the error is only in the picture) | 3 / 3 (88, 75, 67 s) | 0 / 3 (41, 31, 72 s) |
| `psscript` (PowerShell 5.1) | 0 / 3 (465, 431, 356 s) | 0 / 3 (240 s, time limit 900 s, 548 s) |
| `longcontext` (15 changes to 20 modules) | 0 / 3 (278, 557, 318 s) | 0 / 3 (305, 108, 122 s) |
| **Sum** | **9 / 15** in 3970 s | **3 / 15** in 3679 s |
| Rules followed | 43 / 66 (65 %) | 34 / 66 (52 %) |

Raw values in this run: `local-coder` 63 tok/s, `local-fast` 129 tok/s.

Working rules followed, per rule (what the rules mean: [extending.md](extending.md)):

| Rule | `local-coder` | `local-fast` |
|---|---|---|
| `readme` (README names the new feature) | 7 / 15 | 4 / 15 |
| `tests` (test for the new feature) | 6 / 15 | 2 / 15 |
| `config` (new value in the configuration file) | 0 / 6 | 0 / 6 |
| `docstrings` (description on new functions) | 12 / 12 | 11 / 12 |
| `headers` (header comment in new scripts) | 3 / 3 | 2 / 3 |
| `nodeadcode` (no commented-out code) | 15 / 15 | 15 / 15 |

Assessment:

- **`local-coder` stays the default.** Extending, refactoring and fixing bugs from a picture
  succeed in every run. `local-fast` generates twice as fast but passes only 3 of 15 runs and
  reports the failed ones as done too.
- **`local-fast` reads the picture, but not precisely.** In all three runs of `screenshot` it
  named both errors correctly and fixed them, but overlooked the third spelling (`0.5h`) in
  the same call in the screenshot.
- **PowerShell 5.1 is the weakest point of both models** (0 of 6). Every run failed on a
  different peculiarity: error message on standard output instead of stderr, exit code 1
  instead of 2, `total: null` or an object instead of a list with exactly one entry, an extra
  output line. The scripts were nearly right each time.
- **`longcontext` fails on the context, not on ability.** In four of the six runs Claude Code
  broke off with "Autocompact is thrashing": the context of 64k was full again right after
  compacting. The two runs that went through had 14 of 15 and 13 of 15 changes right. That
  speaks for more context (E2 in the [roadmap](roadmap.md)).
- **The working rules only partly work.** What comes about on the side while writing code
  (descriptions, no dead code) is almost always right. What is a step of its own (README,
  test, value into the configuration file) happens in less than half of the runs with
  `local-coder`, the value in the configuration file never.
- **Limits of the measurement:** three runs per task are few; the rule check is a mechanical
  approximation (it sees whether a README was changed, not whether the text is good);
  `local-qwen38` was not measured on the new tasks.

## Current choice (2026-11-14 evening)

Since the switch to llama.cpp every GGUF file is a candidate, not only the catalogue of
Ollama. Three candidates were measured against the previous default model, all with the lean
tool set ([agent.md](agent.md)), every task three times per run.

| Profile | Model | Easy tasks (9 runs) | `planner` (3 runs per pass) | Generation speed | Uncensored |
|---|---|---|---|---|---|
| **`local-coder`** | Qwen 3.6 27B Heretic v2 | 9 / 9 in 673 s ¹, 9 / 9 in 327 s | 3 / 3 in 461 s, 3 / 3 in 474 s | 60 tok/s | yes |
| `local-fast` | Qwen 3.6 35B-A3B Heretic | 9 / 9 in 266 s | 1 / 3 in 846 s | 83 tok/s ² | yes |
| `local-qwen38` | Qwen 3.8 27B Heretic (the default until then) | 9 / 9 in 375 s | 3 / 3 in 904 s, 2 / 3 in 1521 s | 50 to 55 tok/s | yes |
| no profile | gpt-oss 20B | 9 / 9 in 166 s | 1 / 3 in 237 s | 211 tok/s | no |
| no profile | qwen3-coder 30B (formerly `local-fast`) | 7 / 9 in 1709 s ³ | not measured | 145 tok/s | no |

¹ In the first pass right after a restart of the server the generation speed was 37 instead
of 60 tok/s. The cause is not checked; the second pass shows the usual value.
² Measured in the benchmark. `Test-Model.ps1` shows 141 tok/s with its short prompt.
³ With the full tool set, time limit 420 s. With the lean set it also ran into the loop, the
run was broken off.

Assessment:

- **The easy tasks no longer separate.** All usable models pass them. The new task `planner`
  (fix bugs in two modules after a specification, add a module and a command, hidden edge
  cases) separates clearly.
- **Qwen 3.6 27B is the most reliable model and the fastest at `planner`.** Six of six runs
  passed, 135 to 189 s per run. Qwen 3.8 27B passed five of six and needed 216 to 600 s; one
  run exceeded the time limit although the files were already right. It thinks longer without
  the result getting better. Qwen 3.6 also manages with its built-in chat template.
- **The fast models fail at the harder task.** Qwen 3.6 35B-A3B and gpt-oss 20B each passed
  one of three runs. gpt-oss once left a file with a syntax error and once stopped after three
  rounds without creating the new module.
- **Six runs per model are few.** The gap between the two 27B models in time points the same
  way in both passes; the difference of one failed run alone would be no proof.
- **Not checked:** how often the models refuse requests. The statements "uncensored" come from
  the model cards.

**Decision:**

- `local-coder` (short name `unzensiert`) is now Qwen 3.6 27B Heretic v2.
- `local-fast` (`fast`, until 2026-11-18 `schnell`) is now Qwen 3.6 35B-A3B Heretic: for
  simple, clearly bounded tasks in which speed counts. Unlike its predecessor it is uncensored
  and ends reliably.
- `local-qwen38` (`qwen38`) stays selectable for comparison.
- gpt-oss 20B and qwen3-coder 30B no longer have a profile. The file of qwen3-coder 30B is
  deleted; that of gpt-oss 20B still lies as a hard link in the model folder.

Sources of the candidates:
[Qwen3.6-27B Heretic v2](https://huggingface.co/llmfan46/Qwen3.6-27B-uncensored-heretic-v2-Native-MTP-Preserved-GGUF),
[Qwen3.6-35B-A3B Heretic](https://huggingface.co/llmfan46/Qwen3.6-35B-A3B-uncensored-heretic-Native-MTP-Preserved-GGUF).

In `benchmark.md` and `results.jsonl` the measurements carry today's profile names: what was
measured as `cand-qwen36-27b`, `cand-qwen36-35b`, `cand-gpt-oss-20b` and under the old meanings
of `local-coder` and `local-fast` appears there as `local-coder`, `local-fast`, `gpt-oss-20b`,
`local-qwen38` and `qwen3-coder-30b`.

### Why qwen3-coder 30B did not stop

The cause of the loop is found. qwen3-coder 30B often ends its final answer with a started
`<tool_call>` and the end token. As soon as the text `<tool_call>` appears, llama.cpp switches
on a grammar that forces a complete tool call. The model may no longer stop at that point and
calls some tool; after its result this repeats. Ollama silently dropped the started call,
which is why it did not happen there.

The behaviour can be reproduced without Claude Code with a single request. Fewer tools change
nothing about it, and `llama-server` has no option to switch off the forced grammar. The
solution was therefore another model.

## State after the switch to llama.cpp (2026-11-14 afternoon)

In this and the following sections `local-coder` means Qwen 3.8 27B Heretic (today
`local-qwen38`) and `local-fast` qwen3-coder 30B.

Run `llamacpp`: both profiles, every agent task three times, llama.cpp build b12359.

| Profile | Passed | Time for 9 runs | Generation speed | Prompt speed | Comparison Ollama |
|---|---|---|---|---|---|
| **`local-coder`** (`unzensiert`) | 9 / 9 | 431 s | 58 tok/s | 1488 tok/s | 9 / 9 in 993 s, 58 tok/s, 949 tok/s (run `repeat3`) |
| `local-fast` (`schnell`) | 7 / 9 | 1709 s | 145 tok/s | 3835 tok/s | 3 / 3 in 172 s (one run per task), 140 tok/s, 2744 tok/s |

Assessment:

- **`local-coder` finishes much sooner through llama.cpp:** 431 s instead of 993 s for the
  same nine runs, all passed. The generation speed per token stayed about the same (50 to
  68 tok/s in single measurements). What got faster is reading the prompt (about 1490 instead
  of 950 tok/s), and the runs needed fewer rounds (9.8 instead of 11.3 on average).
- **The comparison is not clean.** Several things changed at once between the two runs:
  backend, GPU split (70:30 instead of 65:35), chat template, the new working rules in the
  system prompt and possibly the version of Claude Code. Which share goes back to what is not
  measured.
- **`local-fast` is worse through llama.cpp.** One run gave a wrong result, one exceeded the
  time limit, and the passed runs of the task `bugfix` needed 214 to 300 s. The model solves
  the task but does not stop afterwards: it keeps calling tools (`ReportFindings`, notes into
  the memory folder, `Skill`), up to 56 rounds. The same task through Ollama on the same day:
  40 s, 13 rounds (one run). Without the working rules the behaviour happened as well (one run,
  time limit). The cause is **not settled**; sampling values and chat template were checked
  and are inconspicuous. Until then for `schnell`: watch it in the session and stop it when it
  keeps going after the solution.
- **Recommendation:** `local-coder` stays the default and is now also the faster profile in
  time per task.

A first run with the label `llamacpp` (still in `results.jsonl`, replaced by the second in the
report) was distorted: the working folder was inside the repository, and Claude Code loaded its
`CLAUDE.md` into the tasks. Since then the working folder is outside (`workDir` in
`config\benchmark.json`).

## In short (Ollama, runs of 2026-11-13)

Every agent task ran **exactly once**. Because models are random, a single run is only an
indication, above all for the times. For the three uncensored models with MTP there is a
repeated measurement of 2026-11-14, see below; it contradicts the ranking of the times in this
table.

| Profile | Model | Tasks | Time for all three | Generation speed ¹ | Uncensored |
|---|---|---|---|---|---|
| `local-fast` (`schnell`) | `qwen3-coder:30b` | 3 / 3 | 172 s | 137 tok/s | no |
| – | `qwen3.8:27b` | 3 / 3 | 252 s | 60 tok/s | no |
| **`local-coder`** (`unzensiert`) | `unc-heretic` | 3 / 3 | 653 s | 55 tok/s | yes |
| removed | `unc-blackfrost` | 3 / 3 | 289 s | 55 tok/s | yes |
| removed | `unc-coletti` | 3 / 3 | 326 s | 53 tok/s | yes |
| removed | `qwen3.8-EfficientThink-uncensored:27b` | 3 / 3 | 536 s | 26 tok/s | yes |

¹ With the GPU split of 65:35 set at the time, empty context. See [gpu-tuning.md](gpu-tuning.md).

**Decision (2026-11-14):** `local-coder` is now based on `unc-heretic`. In the repeated
measurement (see below) it passed all runs like the others, had the most even times and
according to its model card refuses least (0–1 %). `unc-blackfrost`, `unc-coletti` and the
first uncensored model (`local-legacy`) were deleted, as were the GGUF files; for a new test
they have to be downloaded again.

**Decision (2026-11-13), superseded:** `local-coder` was based on `unc-blackfrost`. It is twice
as fast as the previous uncensored model, passed all tasks in the shortest time of the
uncensored candidates and according to its model card refuses 2.4 %. For pure speed there is
`local-fast`.

## Uncensored models with MTP

The official Qwen 3.8 models contain an MTP head (multi-token prediction): the model drafts
several tokens ahead and checks them in one step. llama.cpp uses that as speculative decoding
when the profile sets `draft_num_predict`. That doubles the speed (measured: `qwen3.8:27b`
28 tok/s without, 60 tok/s with MTP). The previous uncensored variant lost its MTP head when it
was modified.

Three uncensored variants with an embedded MTP head were downloaded from Hugging Face and
imported with `scripts\Import-Gguf.ps1` (settings taken over from `qwen3.8:27b`). All in
Q4_K_M:

| Ollama name | Source | Method | Refusals according to the card | MTP hits |
|---|---|---|---|---|
| `unc-blackfrost` | Blackfrost-AI/Qwen3.8-27B-ABLITERATED-GGUF | abliteration | 2.4 % | 70–76 % |
| `unc-heretic` | 0bserverx/Qwen3.8-27B-Heretic-Abliterated-Uncensored-GGUF (`RVN-Q4_K_M-mtp.gguf`) | Heretic/ARA, very close to the original | 0–1 % | 72–78 % |
| `unc-coletti` | JonathanColetti/Qwen3.8-27B-Uncensored-GGUF | Heretic | 12 % | 77–78 % |

The refusal rates come from the model cards and were not checked here. All three passed the
agent tasks. The differences in time (289 s to 653 s) come mostly from thinking phases and
numbers of rounds of different length, not from the token speed, which is the same for all.

### Repeated measurement (2026-11-14, run `repeat3`)

Each of the three tasks ran three times per model, so nine runs per model. Together with the
single run of Nov 13 that makes four passes.

| Model | Passed | Time per pass (all three tasks) | Mean of 4 passes ² | Range per task | Rounds per task |
|---|---|---|---|---|---|
| `unc-coletti` | 9 / 9 | 363 s, 263 s, 389 s | 335 s | 65–181 s | 15.7 |
| `unc-heretic` | 9 / 9 | 350 s, 334 s, 309 s | 412 s | 59–156 s | 11.3 |
| `unc-blackfrost` | 9 / 9 | 706 s, 638 s, 331 s | 491 s | 65–412 s | 14.2 |

² Including the single run of Nov 13 (326 s, 653 s, 289 s).

Assessment:

- **There is no measurable difference in quality.** All three passed every one of the twelve
  runs, no run exceeded the time limit of 420 s.
- **The ranking of Nov 13 was not confirmed.** `unc-blackfrost` was fastest in the single run
  and is slowest and most erratic in the repetition: one run of the task `feature` took 412 s,
  just below the time limit. `unc-heretic` was slowest in the single run and is the most even
  in the repetition.
- **The spread is larger than the gap between the models.** The same task with the same model
  took anywhere between 122 s and 412 s. Four passes are therefore only enough for a rough
  statement: `unc-coletti` and `unc-heretic` are about level, `unc-blackfrost` rather behind.
- The token speed is still the same for all (58 to 62 tok/s in this run).

Not tested: `ajgazin/Swift-Qwen3.8-27B-Uncensored-Dynamic-MTP-GGUF` (15 % refusals, licence
with a revenue limit) and `cyjin-yl/...-Cyber-agentic` (specialised in offensive security,
only IQ4_XS, according to its card cut to a runtime of its own).

## Findings

### 32k context is not enough for Claude Code

With 32k almost all models failed that pass with 64k:

| Model | 32k | 64k |
|---|---|---|
| `local-coder` | 0 / 3, all at the time limit | 3 / 3 |
| `qwen3-coder:30b` | 0 / 3 | 3 / 3 |
| `qwen3.8:27b` | 3 / 3, but 282 to 376 s | 3 / 3, 41 to 142 s |

Claude Code takes a large part of the context with its system prompt and tool descriptions. At
32k the rest fills up after a few rounds, Claude Code compacts constantly ("Autocompact is
thrashing") or breaks off. In the bugfix task `qwen3-coder:30b` answered with 32k that it could
not edit code because of "restrictions", presumably because parts of the prompt were lost.
**Set at least 64k.** More than 64k brought nothing in this run (`devstral-small-2` with 96k,
`mimo-v2.6` with 128k).

### Dropped

| Model | Result | Reason |
|---|---|---|
| `deepseek-r1:32b` | 0 / 3 | Cannot call tools, so it has no access to files. With 64k also only 83 % on the GPU and slow at 8 tok/s. |
| `qwen3:8b` | 0 / 3 | Fast (140 tok/s), but too weak. Debugging ended in the compaction loop. |
| `devstral-small-2:24b` | 1 / 3 | In the bugfix task it printed the tool call as text (`Bash{"command": ...}`) instead of running it, so the session ended after one round. The tool format does not fit Claude Code through Ollama reliably. |
| `mimo-v2.6:9b-q8_0` | 2 / 3 | Close, but with real mistakes (multifile: printed the subtotal instead of the total). Remarkable for a 9B model, too unreliable as the default. |
| `flint:40b` | - | Not installed, not measured. |

### Speed

- `qwen3-coder:30b` is a mixture-of-experts model: 30 billion parameters, of which only a small
  part is active per token. Hence 140 tok/s with a VRAM need similar to the 27B models
  (21.2 GB with 64k).
- `qwen3.8:27b` is more than twice as fast at 56 tok/s as the uncensored variant (25 tok/s),
  although both are based on the same base model. The file is smaller (16.5 GB instead of
  18.5 GB), so presumably quantised differently. The exact cause is not checked.
- The value 14.6 tok/s for `qwen3.8:27b` with 32k is an outlier. The thinking measurement in
  the same run gives about 49 tok/s.
- Load times are not a property of the models: the first combination of a model loaded from
  disk (34 to 56 s), the second from the file cache of Windows (4 to 10 s).

### Do not overrate the raw value "tool calls"

`mimo-v2.6` failed the simple tool test (`FAILED` in the raw values), but worked with tools in
the agent tasks through Claude Code. The agent tasks are what tells.

## Next steps

- Measure `local-qwen38` on the five new tasks, if it becomes a candidate again.
- Measure more context (E2) and notes on PowerShell 5.1 (done, see above) on `longcontext` and
  `psscript`: [roadmap.md](roadmap.md).
- Check the refusal rate of the uncensored models ourselves instead of believing the model
  card.
- Measure the changes one by one (GPU split, working rules, thinking effort, MTP length), each
  as a run of its own with `-Label`. Procedure: [extending.md](extending.md).

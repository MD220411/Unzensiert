# Roadmap

What comes next so the local coder becomes safer, more reliable, more economical and faster,
and builds software that can be maintained and extended for years. As of 2026-11-16.

**How the plan is used:** work through it from top to bottom. Every point says how to measure
whether it helped. A finished point moves with its measurement into the
[development log](devlog.md) and is struck out here. A point without measurable effect is
taken back.

**How solid a statement is:**

| Mark | Meaning |
|---|---|
| measured | shown on this computer with `Test-Model.ps1`, `Benchmark-Models.ps1` or a run in the development log |
| documented | stated in the documentation or source code of Claude Code or llama.cpp, not tried here |
| assumption | plausible but unchecked; measure before deciding |

## Starting point

| Area | State | Evidence |
|---|---|---|
| Speed | `local-coder` 57 to 65 tokens/s, `local-fast` 130 to 137, reading about 1500 tokens/s | measured, `logs\model-tests.log` |
| Reliability | `local-coder` passes all 24 runs of the four older tasks and 14 of 15 of the five new ones (the long task 2 of 3); `local-fast` 3 of 15 (before stage 3) | measured, [model-choice.md](model-choice.md) |
| Context | 128k (all three profiles), of which about 5200 tokens go to system prompt, tools and rules before the first question is asked | measured, server log |
| GPU memory | `local-coder` takes 15.6 of 16.3 GB and 10.4 of 12.3 GB; 0 after the session | measured |
| Images | readable by pasting and through `Read` | measured, [models.md](models.md) |
| Protection | the server requires a key; a guard blocks destructive commands and asks about delicate ones. Commands still run without a sandbox on the real computer. | measured, [security.md](security.md) |
| Measurability | nine tasks (Python, PowerShell, image, long context, refactoring), each with a reference solution and self-test | measured, `Test-Tasks.ps1` |
| Rule adherence | with the closing check `local-coder` follows 89 % of the checked working rules (65 % before): README and test 15 of 15, value into the configuration file 0 of 6, with the project template 5 of 6. Cost: about a quarter more run time than without the closing check | measured, [model-choice.md](model-choice.md) |
| Way of working | `New-Project.ps1` creates projects with `CLAUDE.md`, check command, git hook and decisions folder; workflows `/feature`, `/bugfix`, `/review` | measured, `Test-Templates.ps1`; workflows only on one task |

The biggest gaps now are the unchecked places: operation at the terminal (S8, N8), the linters
in the check command (N9) and the value in the configuration file without the project
template. Memory is almost used up with 128k context; more speed or a larger quantisation
only come at the cost of context or with other hardware.

## Hardening for real projects (priority since 2026-11-16)

During real work on an ESP32 firmware `local-coder` showed two classes of errors the benchmark
does not measure: **made-up facts** (pins, voltages, configuration keys) and
**contradictions between files** after a change. A cross-check with a large model found
both. The user's goal: projects that become reliable for the long run with the local coder.
Parity of a 27B model with large models cannot be reached through settings (assumption, not
measured); the goal applies to the whole system of model, rules and check programs. On
2026-11-16 the user chose "harden the setup" and the local variant (A) for the second look.

| No. | Step | State |
|---|---|---|
| H1 | One source of truth per project (`facts\facts.json`) and comparison against documentation and code in the check command | done 2026-11-17 ([projects.md](projects.md)) |
| H2 | Rule "check facts instead of guessing" in `coding-rules.md` and the `CLAUDE.md` of the template | done 2026-11-17; effect not measured (H4) |
| H3 | Second look: after larger changes a second local model (`local-qwen38`) checks the diff in a fresh context | done 2026-11-17 ([agent.md](agent.md)); measured on one case, where `local-coder` found more as reviewer. Benchmark `h3-qwen38` interrupted after 9 of 42 runs: 1 real finding, no false alarm, 53 % more time. Open: the remaining tasks and `local-coder` as reviewer (`h3-coder`) |
| H4 | Benchmark tasks for faithfulness to facts and consistency across files | tasks `datenblatt` and `pinwechsel` done 2026-11-17 ([extending.md](extending.md)); `local-coder` passes both 3 of 3, `facts` 6 of 6 ([development log](devlog.md)). Open: comparison without the facts file; effect of the second look with `Benchmark-Models.ps1 -Git` |

## Order

| Stage | Content | Effort | Goal |
|---|---|---|---|
| 1 | Safety net: done on 2026-11-15 ([development log](devlog.md), [security.md](security.md)). Left: S8 | one session at the terminal | A mistake of the model destroys nothing on the computer, a typo in `config\` shows up at once |
| 2 | Measurability: done on 2026-11-15 ([development log](devlog.md), [model-choice.md](model-choice.md)) | | Every later change can be checked against tasks that resemble real use |
| 3 | Way of working: done on 2026-11-15 ([development log](devlog.md), [projects.md](projects.md), [agent.md](agent.md)). Left: N8, N9, Q9 | | Every new project starts maintainable, tests and checks run without the model's help |
| 4 | Fine-tuning, first part done on 2026-11-16 (E1, E2, G1, G2, Q9: [model-choice.md](model-choice.md)). Left: E3 to E5, G3, G4, Q4, Q5 (Q6 is done as H3, G5 ongoing) | one measuring run each | More context and speed, each backed by a number |
| 5 | Larger steps: S6, S9, Q7, G6 | open | Sandbox, model change, hardware |

## Security

An uncensored model refuses nothing, not even an instruction hidden in a file or web page it
has read. The protection therefore has to lie outside the model: in the server, in the agent
and in git.

**Principle (given by the user, 2026-11-15):** the protection serves your own computer and
your own data. It does not judge what the model is working on, and it does not get in the
way of normal work. Every proposal below is measured against that; when in doubt, the
protection asks instead of blocking.

Done are the key for the server, the guard before every tool call (also for credentials) and
the git note at start: [security.md](security.md).

| No. | Proposal | Why | Check |
|---|---|---|---|
| S5 | **Origin and checksums of the model files.** A field `sha256` per file in `models.json`, `Add-Model.ps1` checks it. Record the source of the three `mmproj` files. | Model files are foreign code for the graphics card. The source of the `mmproj` files is not recorded. | `Add-Model.ps1` rejects a file with a wrong sum |
| S6 | **Risky work in WSL2.** Claude Code in WSL2 with the sandbox switched on (writing only in the project folder, network only to allowed addresses), `llama-server` stays on Windows. First try the switch `--restricted`, which limits the file tools to the working folder. | The only way to really lock commands in (documented). Effort: network between WSL2 and Windows, a second installation. | A write attempt outside the project folder fails |
| S7 | **Check dependencies without holding up work.** `pip-audit` or `npm audit` in the check command of the project (N9); no question at every installation. | Packages from the internet are the usual way for malicious code onto your own computer; a local model occasionally makes up package names (assumption). A question at every `pip install` would get in the way of normal work. | A package with a known vulnerability makes the project check fail |
| S8 | **Confirm the question in a real session.** Trigger a command at the terminal where the guard asks (for example `git reset --hard` in a test folder) and check that the question appears with its reason and that yes and no both work. Then look through `<installRoot>\logs\guard.log` after a few days of work: loosen rules that fire during normal work. | So far blocks and questions are checked in runs without a user; there a question counts as no. Only everyday use shows whether the guard gets in the way. | The question appears; no entry in the guard's log that concerns normal work |
| S9 | **Make blocks harder to get around.** Check scripts that the model writes and then starts with the same rules before they start. | Measured: after a block the model looked for another spelling on its own. A guard that only sees the command line does not notice what is in a started file. | Test case: a blocked command in a `.ps1` or `.sh` file is recognised when it starts |

## Quality

Done are the tasks modelled on real use and the measurement of rule adherence
([extending.md](extending.md)), the notes on PowerShell 5.1 (`psscript` 9 of 9 instead of
0 of 6) and the closing check ([agent.md](agent.md)). Baseline for everything further,
`local-coder`, run `stufe4`: 14 of 15 runs passed in 4903 s, 89 % of the rules followed,
`longcontext` 2 of 3.

| No. | Proposal | Why | Check |
|---|---|---|---|
| Q4 | **Limit the thinking effort.** Measure `reasoning-budget` in steps. | Open point from the development log. Fewer thinking tokens save time and context; whether quality suffers is open (assumption). | `planner` six times per step: rate and time |
| Q5 | **Larger quantisation.** Q5_K_M of the 27B model instead of Q4_K_M. The file is downloaded (checksum equal to the one given by the source), profile `local-coder-q5`. Measured: fits only with 64k context (split 66/34), 54 instead of 61 tok/s. Open is the comparison of quality; a gain would have to outweigh the loss of 64k context. | More bits per weight means fewer computing errors; whether that shows in agent tasks is open (assumption). Costs memory and a little speed. | `planner` and the five newer tasks, speed from `Test-Model.ps1` |
| Q7 | **Watch models, with a fixed procedure.** Look at candidates once a month (last named: Devstral Small 2, newer Qwen coder models; figures of the makers, unchecked here). Change only when the new model passes the whole benchmark at least as well. | According to its maker Qwen 3.8 was better, and in our own measurement worse than Qwen 3.6 (measured). Our own measurement beats leaderboards. | An entry in [model-choice.md](model-choice.md) per candidate |

## Sustainable development

The coder should build projects that someone still understands and extends two years from
now. Rules in the prompt are not enough for that. The structure has to be in the project,
and a program has to do the checking.

Done are the project template with `New-Project.ps1`, the short `CLAUDE.md`, the folder for
decisions, the check command with git hook, interfaces and versions in the template and the
workflows: [projects.md](projects.md). Measured: with `CLAUDE.md` and check command
`local-coder` follows 91 % of the rules instead of 85 %, the value in the configuration file
succeeds in 5 of 6 runs instead of 0 of 6.

| No. | Proposal | Why | Check |
|---|---|---|---|
| N8 | **Measure decision files and workflows.** A benchmark task in which a change to an interface requires a file in `docs\decisions\`; `/feature` and `/bugfix` on all fitting tasks; try workflows and closing check in a real session at the terminal. | The folder and the workflows exist, but whether the model records decisions on its own is not measured. `/feature` is only measured on `extend` (2 of 3, rules 15 of 15). | Rate per workflow; decision file in three of three runs |
| N9 | **Extend the check command.** Install `ruff`, `PSScriptAnalyzer`, `gitleaks` and `pip-audit` (S7) and try the optional steps in `config\check.json` of the templates; the same command in GitHub Actions. | The linter steps are in the template but unchecked because the programs are missing. A search for secrets is missing entirely. | Deliberately built-in errors (unused import, key in the code) make the command fail |
| N6 | **Small steps.** One task per session, then `/clear`. One commit per finished change. Break large plans into a list in `docs\` first, then point by point. | 64k context fills up fast; after compacting, details are missing. Small commits can be undone one by one. | Experience, note it in the development log |

## Efficiency

What is scarce are the context and the memory of the faster graphics card. Done: image
encoder on the RTX 3060 and 128k context ([model-choice.md](model-choice.md)).

| No. | Proposal | Why | Check |
|---|---|---|---|
| E3 | **Limit tool output.** Lower the limit for the output of `Bash`; rule: send long output into a file and read it selectively. | A single long test output can cost several thousand tokens (assumption about the magnitude). | Tokens per task in the benchmark |
| E4 | **Keep the context cache across breaks.** Try `slot-save-path`. | After the idle limit and after unloading, the conversation is read in again: about 40 s at 60k tokens (computed from 1500 tokens/s). | Time of the first answer after waking up |
| E5 | **Keep the system prompt stable.** Try the switch `--exclude-dynamic-system-prompt-sections` and shorter tool descriptions (for `claude-local`). | The switch moves changing details out of the system prompt (documented, `claude --help`); whether the server's cache then hits more often is open. The cache itself works: in the log only 385 of 6300 tokens were read in anew (measured). | Tokens read in anew per request in `server.log` |

## Speed

| No. | Proposal | Why | Check |
|---|---|---|---|
| G2 | **GPU split, if context becomes free.** 79/21 instead of 70/30. | Measured at 64k: 65.5 instead of 61 tok/s, reading 1635 instead of 1316 tok/s. The memory for it is taken since 128k context; the question comes up again with G6 or a smaller context. (Today the planner computes the split, [planner.md](planner.md).) | `Test-Model.ps1` |
| G3 | **Background requests.** Count in the `server.log` of a real session how often Claude Code sends side requests and whether the whole conversation is read in again afterwards. If so: a second slot (`parallel = 2`) or a small model on the 3060 for these requests. | With one slot a side request can push the cache of the main conversation out (assumption). It does not happen in runs with `-p`. | Tokens read in anew per request |
| G4 | **Distribute tasks.** `local-fast` for searching, explaining and small changes, `local-coder` for everything hard. | `local-fast` is twice as fast and passes the easy tasks (measured), but fails at `planner`. | Time per kind of task |
| G5 | **Keep llama.cpp up to date.** Bring in new versions with the procedure in [backend.md](backend.md). Last b12433 on 2026-11-16: 13 of 15 in 4463 s, 91 % rules, speed the same ([development log](devlog.md)). | MTP and computing with several cards keep getting faster. Repeat the benchmark after every change. | `Benchmark-Models.ps1 -Label <version>` |
| G6 | **Hardware.** A card with 24 GB instead of the RTX 3060, or the second card in a slot with more lanes. | The PCIe x4 connection slows things down ([gpu-tuning.md](gpu-tuning.md)). More memory allows Q5 or Q6 together with 128k context and the faster split. Biggest lever, the only one that costs money. MTP length, split and context are exhausted (measured). | Benchmark before and after |

## Maintaining this project

| No. | Proposal | Why | Check |
|---|---|---|---|
| P3 | **Tests for the building blocks.** Pester tests for `lib\Config.ps1`, the generated `models.ini` and `lib\Session.ps1`. | So far only the run with a loaded model checks them. The logic around it grows. | Tests run as part of `Test-Setup.ps1` |
| P4 | **Report the bug to llama.cpp.** The wrong order of text and tool result ([models.md](models.md)) as an issue. | Then the block "agent fix" can go away some day, and the templates stay closer to the original. Needs the user's GitHub account. | Issue created |
| P5 | **Open points from the development log.** Confirm `/model` and Continue in real use, check refusal rates yourself, measure the effect of the working rules alone (run with and without `coding-rules.md`, rate "rules followed"). Look at refused calls in the benchmark: the model wrote the working folder with the wrong upper and lower case or put `cd ... &&` in front of the command. | Open since Nov 14. | Entries in the development log |

## Sources of the research

- Claude Code, sandbox: <https://code.claude.com/docs/en/sandboxing> (Windows without a
  sandbox, settings of the sandbox)
- Unsloth, Claude Code with local models: <https://unsloth.ai/docs/basics/claude-code>
  (cache, switch for the system prompt, sampling)
- llama.cpp, documentation of the server as of b12359: `tools/server/README.md`
  (sleeping when idle, router, cache options), source code `tools/server/server-chat.cpp`
- Stack Overflow Blog, "Coding guidelines for AI agents":
  <https://stackoverflow.blog/2026/03/26/coding-guidelines-for-ai-agents-and-people-too/>
- Sonar, "Seven habits of highly effective AI coding":
  <https://www.sonarsource.com/blog/seven-habits-of-highly-effective-ai-coding/>
- Marmelab, "Agent Experience": <https://marmelab.com/blog/2026/01/21/agent-experience.html>
- Model overviews (figures of the makers, not measured here):
  <https://insiderllm.com/guides/best-local-coding-models-2026/>,
  <https://www.promptquorum.com/local-llms/best-local-llms-for-coding>

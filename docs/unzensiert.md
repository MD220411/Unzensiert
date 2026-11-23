# Unzensiert: the own agent

`unzensiert` is the coding agent of this project. It works in the current folder with a local
model of `llama-server`: it reads and changes files, runs commands and checks its work. It
needs no further program and no cloud. It talks to the OpenAI-compatible interface of the
server (`/v1/chat/completions`, streamed, with tools) and is written entirely in PowerShell
5.1, which is present on every Windows.

Operation, tools, working rules, guard, closing check, second look and the workflows
`/feature`, `/bugfix`, `/review` are the same as with `claude-local`. Unzensiert draws its
terminal itself, in the look of the project ([style.md](style.md#the-terminal-of-unzensiert)).
`claude-local` (Claude Code with the local server, [agent.md](agent.md)) stays for
comparison; the benchmark can measure both.

## Measured against Claude Code

All eleven benchmark tasks, each three times, with `local-coder`, both agents under the same
conditions (run `vergleich2`, 2026-11-18):

| | Unzensiert | claude-local (Claude Code) |
|---|---|---|
| passed | 27 / 33 | 29 / 33 |
| time (sum of the medians per task) | **1,629 s** | 2,160 s |
| rounds (likewise) | **268** | 418 |
| tokens written (likewise) | **98,591** | 122,004 |
| working rules | 88 / 96 | 86 / 96 |
| time limit reached (counts as failed) | 1 | 1 |

Unzensiert was faster on all eleven tasks: 25 % less time and 36 % fewer rounds altogether.
The difference in passing is within chance (Fisher's exact test, p = 0.73); all failures with
a wrong result are mistakes of the model that also happened with Claude Code.

## Using it

| Command | Effect |
|---|---|
| `unzensiert` | conversation in the terminal with the default model (`model` in `config\agent.json`) |
| `unzensiert "task"` | the same, starting right away with this request |
| `unzensiert -Model fast` | another model: short name from `aliases` or profile name |
| `unzensiert -p "question"` | one request without a terminal, the answer as text; the request can also come through a pipe |
| `unzensiert -p --output-format json ...` | the same as one JSON line (see below) |
| `unzensiert -c` | continue the last conversation in this folder |
| `unzensiert --resume` | choose an earlier conversation (`--resume <id>` directly) |
| `unzensiert --permission-mode edits` | rights mode `ask`, `edits`, `plan` or `all` (the names of Claude Code work too) |
| `unzensiert --allowedTools "Bash(python:*)"` | allow these calls without a question, written as in Claude Code |
| `unzensiert --max-turns 30` | at most this many rounds with tool calls |
| `unzensiert --trust` | use the instructions, the check command and the git programs of this folder without the question about [trust](security.md#trust-in-a-folder), for this run; only for folders whose content you know |
| `unzensiert -OnExit keep` | keep the models loaded after the end (`unload`, `stop`, `keep`) |
| `unzensiert --version`, `--help` | version, help |
| `unzensiert --update` | look for a new release now and bring it in |
| `unzensiert --updates on` / `off` | switch automatic updates on this computer on or off |

The server starts along when needed, the model loads with the first request. When the last
session ends, the models are unloaded as with `claude-local` (`onExit` in
`config\agent.json`).

## In the conversation

| Key or input | Effect |
|---|---|
| Enter | send |
| Shift+Enter (or Ctrl+Enter) | new line |
| Up/Down arrow | earlier input (saved in `<installRoot>\unzensiert-history.txt`) |
| Esc or Ctrl+C while the model works | stop; a running command is ended with all its child processes |
| Shift+Tab | switch the rights mode (`ask` → `edits` → `plan` → `all`); text you had started goes into the list of earlier input |
| Alt+V | paste an image from the clipboard; the model sees it |
| `!command` | run a command yourself; the model sees command and output with the next message |
| `/help` | all commands |
| `/model [name or number]` | switch the model (entries of `picker` in `config\agent.json`) |
| `/gpu [numbers, ids or all]` | choose the graphics cards llama.cpp may use, one or several (`/gpu 2`, `/gpu 1 2`, `/gpu CUDA1`, `/gpu all`); without an argument it lists the cards and asks. The choice is kept in `config\machine.json`; then the planner spreads every agent model over the chosen cards again (a few minutes, llama-server stops for that, Esc stops), see [planner.md](planner.md#choosing-the-cards) |
| `/mode [ask, edits, plan, all]` | set the rights mode or move to the next one |
| `/plan [task]` | plan mode ([below](#planning-before-the-work)); with a task after it, that task goes to the model right away |
| `/compact [what to keep]` | summarise the conversation now |
| `/clear` | new conversation |
| `/resume [number]` | continue an earlier conversation of this folder |
| `/status` | model, context, tokens, rights, project instructions, file of the conversation |
| `/think` | show the model's thinking or only its length |
| `/init` | the model writes an `AGENTS.md` for the project |
| `/feature`, `/bugfix`, `/review` (also `/local:feature` etc.) | workflows from `config\workflows\commands\` ([agent.md](agent.md)) |
| `/exit` | quit |

## What you see

The terminal is described with a picture and all its elements in
[style.md](style.md#the-terminal-of-unzensiert). In short:

- **Welcome:** the picture of the style, next to it version, model, context window, project
  with git state, memory of the graphics cards, rights, project instructions and server; a
  quote and the most important keys. With `-c` or `--resume` it says which conversation
  continues.
- **Status bar** at the bottom, like the status line of Claude Code: mood and model, context
  as a gauge, rights, every graphics card with its memory (NVIDIA, Intel Arc, AMD Radeon),
  folder and git, the speed of the last answer, the time. It stays visible under the text
  while you type and while the model thinks and works; once the window is full, that is its
  bottom edge. In a narrow window the parts take short forms (the cards as gauges with "GPU")
  before the least important ones go. Your own message stands on a coloured bar after
  sending.
- **Activity line** while the model reads, thinks, writes a tool call, a command runs or the
  closing check works: what is happening, for how long, "Esc stops". Title and progress ring
  of the tab in Windows Terminal show the same, even when the window is in the background.
- **Answer** with Markdown (headings, lists, tasks, quotes, tables with aligned columns,
  links), wrapped at word boundaries; code blocks in a frame with the colours of their
  language. After thinking a line "∴ thought for 6.4 s · 365 tokens".
- **Tools** with sign and colour, tick or cross and duration; commands with the beginning and
  end of their output, changes as a diff with line numbers and marked characters; a web
  search with its best results, a web page with its title and how much of it was read.
- **Task list** under every `TodoWrite`: done steps ticked and struck through, the step in
  progress bright, the open ones plain. While the model works on a step, the activity line
  names that step.
- **Questions** in a frame: before a call (see Rights), the questions of the model with
  numbered choices, and the plan with the keys to approve it ([below](#planning-before-the-work)).
- After every request a line with duration, rounds, changed files, tokens and speed; at the
  end of the session a summary.

Colours and glyphs come from the active style (`config\style.json`, section `agent` of the
style file), the texts from `config\unzensiert-texts.json`.

## Rights

The guard decides first in every mode (`config\guard.json`, [security.md](security.md)):
what is blocked never runs, what is delicate always asks. After that the mode applies:

| Mode | Reading (Read, Glob, Grep, commands that only read) | Changing files in the project folder (Edit, EditLines, Write, file commands) | Other commands | Web (WebSearch, WebFetch) |
|---|---|---|---|---|
| `ask` (default) | without a question | question | question | question |
| `edits` | without a question | without a question | question | question |
| `plan` | without a question | refused until you approve the plan | question | question |
| `all` | without a question | without a question | without a question | without a question |

- **Task list, questions and the plan** (`TodoWrite`, `AskUserQuestion`, `PresentPlan`) change
  nothing and reach nobody; they run in every mode without a question.
- **Web:** the question shows the search terms or the address. `a` (always) allows every
  search, or every page of that host (`WebFetch(domain:docs.python.org)`, also the hosts below
  it), for the rest of the session; `--allowedTools "WebFetch(domain:python.org)"` does the
  same from the start.
- **Commands that only read** (`readOnlyCommands`, `readOnlyGit` in `config\unzensiert.json`:
  `ls`, `cat`, `grep`, `git status`, `git diff`, `Get-ChildItem` ...) also run as part of a
  longer line (`cd src && ls`). Only lines that are understood completely count, with the options
  listed in `config\readonly.json`; everything else asks
  ([security.md](security.md#what-runs-without-a-question)).
- **Files that run or are obeyed later by themselves** (git hooks, `.vscode`, `AGENTS.md`, the check
  command ...) ask in `ask` and `edits` every time
  ([security.md](security.md#files-that-run-later-by-themselves)).
- **Network paths, keys and credentials** ask in every mode, also for Read, Glob and Grep.
- **Outside the project folder** Edit and Write ask every time, also after "always" and in
  `edits`; only `all` lets them through without a question.
- **File commands** (`fileCommands`: `mkdir`, `rm`, `mv`, `cp`, `New-Item`, `Remove-Item` ...)
  count as file changes in `edits` when every target lies in the project folder. A target
  outside, in a variable or the project folder itself leads to a question.
- **The question** stands in a frame and shows the command completely and in the colours of its
  shell, for Edit the change as a diff with line numbers, for Write the beginning of the file, plus
  the reason and what "always" would allow. Keys: `y` or Enter yes; `a` always (for this session:
  for commands the program with its subcommand, for interpreters only the script or module, for
  files all changes in the project); `v` shows everything when lines are missing; `n` or Esc no.
  (The German keys `j` and `i` still work.) If the guard asks, the frame is pink, there is no
  "always", and only `y` is a yes. After a no the model waits for your instruction.
- **Without a terminal** (`-p`) every question becomes a refusal with a reason for the model.
  After three refusals in one request it gets the note not to look for further detours; after
  nine the request ends.
- Command lines are split at `&&`, `||`, `;`, `|`, `&` and line breaks as the shell does it; every
  piece must be allowed, `python -c "a; b"` stays one command. A line that cannot be taken apart
  with certainty asks as a whole.
- **Trust:** what a folder brings along (instructions, check command, programs of its git
  configuration) is used after one yes at the start; `--trust` for a run without a terminal
  ([security.md](security.md#trust-in-a-folder)).

## Tools

The model gets the tools from `tools` in `config\agent.json`, the same lean set as Claude Code
under `claude-local` (`Bash,Read,Edit,Write,Glob,Grep`; without Git Bash `PowerShell` instead
of `Bash`). Names and parameters are those of Claude Code, so the same guard checks both
agents. On top come the tools of Unzensiert's own in `addTools` of `config\unzensiert.json`:
`TodoWrite`, `AskUserQuestion`, `PresentPlan`, `WebSearch` and `WebFetch` (the names Claude
Code uses for its tools of the same kind, except `PresentPlan`). A session only
offers what can work in it: questions and the plan only with someone at the terminal; in a
run without a terminal (`-p`) the web tools only when they would be allowed (mode `all` or
`--allowedTools`), because there every question becomes a refusal. The set stays the same
within a session, so the text the server has cached stays valid. The setting `editLines`
adds `EditLines`; it is off, because `local-coder` did not take it up (in a run of all eleven
tasks it used it once in 89 edits). For the guard, the rights of a session and the closing
check `EditLines` is an `Edit`.

**Several calls in one answer:** the model may put several tool calls into one answer (it does
so now and then by itself, for example to read several files at once). They run one after the
other in the given order, each with its own question where one is needed; after a no the rest
of the answer does not run. The setting `parallelToolCalls` (off) also asks for it in the
system prompt and in the description of `TodoWrite`, and a list update that came alone gets a
note to send the next one with the next step. Measured with `local-coder` on the eleven
benchmark tasks, four runs with and four without it: the model groups its calls (1.6 instead
of 1.4 per answer, the list update together with the next step in 130 of 283 cases instead of
never) and needs 13 % fewer rounds, but the time, the written tokens and the share of passed
tasks stay within the spread between runs. It makes nothing faster or better, so it stays off.

| Tool | What it does |
|---|---|
| `Bash` | command in Git Bash, `PowerShell` in Windows PowerShell 5.1; always in the project folder. The command goes into a script file (no trouble with quotes), runs without input, at most `commandTimeoutSeconds` (up to `commandMaxSeconds` when the model asks for more) and is ended with all its child processes. Long output keeps its beginning and end, because that is usually where the error is. Python writes UTF-8 (`PYTHONIOENCODING`); a line that is not UTF-8, such as the localised messages of a `powershell.exe` started from Git Bash, is read in the code page of the console. |
| `Read` | file with line numbers, parts with `offset`/`limit`; the model sees images as images |
| `Edit` | replace text; only after `Read` and only if the file has not changed since. The text must appear exactly once (or `replace_all`). Line endings (CR LF), encoding and byte order mark of the file stay as they were. If it does not find the text, it says whether only indentation or line breaks differ. |
| `EditLines` | only with `editLines`: replace whole lines by their numbers (`start_line` to `end_line`, as `Read` shows them) with `new_text`; the model quotes the first and the last of these lines as proof (`first_line`, `last_line`). If they do not match, nothing changes and the result names the real line and shows the place. The model writes only the new lines instead of copying the old ones into `old_string`. The result names the new numbers, because the lines below move. Same rules as `Edit`: only after `Read`, line endings and encoding stay. |
| `Write` | new file, or replace a file that was read completely. If the file already has exactly this content, it writes nothing and says so. |
| `Glob` | files by pattern (`**/*.py`, `src/*.{ts,tsx}`), newest first, without `.git`, `node_modules`, `__pycache__`, `.venv` |
| `Grep` | content by regular expression (.NET), output `path:line:text`, with `glob`, `ignore_case`, `files_only` |
| `TodoWrite` | the task list: the model always sends the whole list, each step `pending`, `in_progress` or `completed` (other words such as "done" or "in progress" are understood). The terminal shows it; it survives a summary of the conversation and comes back with `-c` and `--resume`. |
| `AskUserQuestion` | one to four questions with two to six choices each, the recommendation first; only with someone at the terminal ([below](#planning-before-the-work)) |
| `PresentPlan` | the plan in Markdown for your approval; only with someone at the terminal ([below](#planning-before-the-work)) |
| `WebSearch` | the best results of a search engine (title, address, excerpt), by default `searchResults` (8) of DuckDuckGo ([below](#research-on-the-web)) |
| `WebFetch` | a web page as text: headings, lists, links, code blocks; `pageChars` (20,000) characters per call, the rest with `offset`. A page is fetched once per session and kept for its further parts. |

## Commits name Unzensiert as co-author

Commits made in a session, by the model or by you with `!git commit`, end with the line
`Co-authored-by: Unzensiert <359525642+Unzensiert-coder@users.noreply.github.com>` (setting
`coAuthor`). GitHub lists the co-authors of a commit next to its author.

- **How:** with git 2.54 or newer the commands of the tools `Bash` and `PowerShell` (and
  `!command`) get a `prepare-commit-msg` hook through their environment (`GIT_CONFIG_COUNT`),
  which adds the line with `git interpret-trailers`. Nothing is written into the repository,
  the project's own hooks still run, and commits made outside Unzensiert stay as they are.
  An amend, or a message that already has the line, does not get it twice. Copies of
  commits that already exist (`rebase`, `cherry-pick`) keep their message; merges and
  reverts made in the session get the line.
- **Older git:** the system prompt asks the model to end each commit message with the line.
  How reliably a local model does that is not measured.
- **The address** is the private address that GitHub gives the account
  [Unzensiert-coder](https://github.com/Unzensiert-coder), a machine account that exists only
  as the identity of Unzensiert. GitHub links the line to that account and shows its picture
  (`docs\images\unzensiert-avatar.png`). This has not been checked on a pushed commit yet.
- **Off:** `"coAuthor": ""`, for one computer in `config\machine.json` under `"unzensiert"`.

## Planning before the work

The system prompt gives the model an order for larger tasks (a new feature, changes in
several files, a new project, more than a few steps); small, clear tasks it does directly:

1. **Research:** read the README, the instructions and the files concerned, look up what it
   is not sure of: with `--help`, in the installed packages and, when the web tools are
   offered, on the web.
2. **Clarify:** where the request leaves decisions open that change the result (behaviour,
   scope, special cases, technology), it asks you with `AskUserQuestion`: up to four
   questions at once, each with concrete choices, its recommendation first. Not what it can
   find out itself or what has a usual answer.
3. **Plan:** the steps go into the task list (`TodoWrite`), small and checkable, tests and
   documentation included; then it shows the plan with `PresentPlan` and waits.
4. **Work:** it goes through the list on its own, one step at a time, and marks each as done
   once it is checked. It asks again only when something comes up that only you can decide.
5. **Check:** before the final report it goes through the request once more, requirement by
   requirement.

**Questions** stand in a frame with numbered choices and what each means. A number chooses,
Enter takes the first (the recommendation), the last number or `o` lets you type an answer of
your own, Esc stops the request. When several choices are allowed, you type their numbers
(`1,3`) or your own text.

**The plan** stands between two edges, written like an answer. Keys: `y` or Enter start;
`e` start and let file changes in the project folder run without asking (mode `edits`); `n`
say what should change (the model revises the plan and shows it again; Enter alone stops);
Esc stops.

**Plan mode** (Shift+Tab, `/plan`, `--permission-mode plan`) holds the model to the first
three steps: every request gets a note that it should research, ask and present a plan;
Edit, EditLines, Write and file commands are refused, commands that only read run, other
commands ask (some only look something up). Once you approve the plan, the session goes back
to the mode you had before plan mode (`ask` if it started in plan mode, `edits` with `e`).
Without a terminal the model gives the plan as its answer.

**Open steps:** when the model wants to end a request in which it used tools while its task
list still has open steps, it gets a note with these steps and goes on, at most
`todoReminders` (2) times per request and not in plan mode. A step it can no longer do it
takes off the list and names in its report. This note comes before the closing check.

**Without a terminal** (`-p`, the benchmark) nobody can answer: the system prompt says so,
`AskUserQuestion` and `PresentPlan` are not offered, and the model decides open questions
itself and names its assumptions in the final report.

**Measured** with `local-coder` on the eleven benchmark tasks, once each, against the version
before on the same evening (so only the task list and the order were in it): the model kept a
task list in all eight larger tasks, after reading the files first, and never in the two small
ones. The tasks passed as before (one failure came from an empty answer of the model, which is
now caught, see [loops](#built-in-help-against-loops)); the time went up by about 10 %,
because every tick in the list is a round of its own. Whether questions and the plan give
better results in real work is not measured; the benchmark has no one to answer.

## Research on the web

`WebSearch` and `WebFetch` are the only way content of the internet gets in and search terms
or addresses get out; everything else stays on the computer. Both ask before they run, except
in mode `all`, and the question shows the search terms or the address
([security.md](security.md#web-access)).

- **Search:** by default the page of DuckDuckGo for browsers without scripts
  (`duckduckgoUrl`), no key needed. Should DuckDuckGo ask for a human check, the search fails
  with that message and the model is told to read known pages with `WebFetch` instead;
  Unzensiert does not try to get around the check. With `"searchEngine": "searxng"` and
  `searxngUrl` it asks a SearXNG instance of your own (JSON format switched on; not tried
  against a real instance yet).
- **Pages:** HTML becomes text: scripts, styles, navigation, footer and side columns go, and
  when the page marks its main part (`<main>`, `<article>`, `role="main"`), only that stays.
  Headings become `#`, list items `-`, links Markdown links with the full address, code
  blocks keep their lines.
  Plain text and JSON stay as they are; other files (PDF, images) are refused.
- **Information, not instructions:** every page and every list of results comes with that
  note, and the system prompt tells the model not to follow instructions it finds there and
  never to put secrets or personal data into search terms or addresses.
- **Requests** name the program honestly (`Unzensiert/<version> (local coding agent)`), wait
  at most `timeoutSeconds` (20) and read at most `maxBytes` (5 MB); Esc stops them.
- **Off:** remove `WebSearch` and `WebFetch` from `addTools` (for one computer in
  `config\machine.json` under `"unzensiert"`); then the system prompt says again that nothing
  leaves the computer.

## Closing check and second look

When the model wants to end an answer in which it changed files, the same closing check runs
as with `claude-local` (`scripts\hooks\Check-Stop.ps1`, `stopCheck` and `review` in
`config\agent.json`, [agent.md](agent.md)): check command of the project, reminder of test,
README and settings, after larger changes the second look. The check command starts code of the
project, so it asks before its first run: `y` for this session, `a` always in this project (until it
or its steps change), `v` shows it, `n` no. Mode `all` runs it like every command, unless you
declined it at the start. For that Unzensiert writes a short
transcript in the format the hook knows from Claude Code (requests and file changes,
`<session>.hook.jsonl`). If the check reports something, the model goes on; the messages name
the agent (`CLAUDE_LOCAL_AGENT=Unzensiert`). Esc also breaks off a long check.

## Context

The window is `ctx-size` of the model profile. After every answer Unzensiert knows the exact
token count from the server and only estimates what came since. When the conversation fills
`compactAt` (80 %) of the window, it first shortens old tool results (older than
`keepRecentRounds` rounds) to `oldToolResultChars` characters and drops the thinking of those
rounds; if that is not enough, the model summarises the conversation and keeps working
afterwards, with the last request and the task list word for word. If a request still does
not fit, it summarises and tries once more.

The thinking of the model stays in the conversation, also that of earlier requests: the chat
templates of the Qwen models show it (`preserve_thinking`), so the text the server has cached
stays the same and only what is new is read in. Measured with `local-coder`: after a request
of eight tool rounds (21,561 tokens) the next request read 33 tokens; with the thinking of the
earlier request removed, as Unzensiert did up to version 1.1, it read 21,288 tokens again
(22 s), because these models can only go back to a saved checkpoint, not to any position.

## Saved conversations

Every conversation is in `<installRoot>\sessions\<project folder>\<start>.jsonl`, one message
per line; images are not saved, only a note. After a summary there is a mark; continuing
(`-c`, `--resume`, `/resume`) begins behind it and gets a fresh system prompt (date, git
state, today's rules). The task list comes back from the last `TodoWrite` call.

## System prompt

`config\unzensiert-prompt.md` with the facts of the session (date, Windows, folder, git with
the branch, shells, whether someone is at the terminal), plus the instructions of the project
(`projectFiles`: `AGENTS.md`, otherwise `CLAUDE.md`, from the repository down to the project
folder, the nearest last, once you confirmed them:
[trust](security.md#trust-in-a-folder)) and the working rules from `rulesFile` in `config\agent.json`.
Parts in `{{if Name}}...{{end}}` (also `{{if !Name}}`, nested) stay only when the session
offers that tool, or for `web` one of the web tools, for `terminal` someone at the terminal:
the order for larger tasks, the questions, the plan, the warning about the web. System
prompt and tool descriptions have about 10,800 characters together in a run without a
terminal and about 14,200 at the terminal with all tools of `addTools` (before the planning
tools 8,900, when the first request of a task measured 2,808 tokens; at the same ratio about
3,400 and 4,500 tokens, not measured). Claude Code first sends about 26,000 tokens to the
local server ([README](../README.md)). The prompt says: answer in the language the user
writes in. With git older than 2.54 it also asks for the co-author line in commits
([above](#commits-name-unzensiert-as-co-author)).

## One-off run and JSON

`unzensiert -p` reads the request from the arguments and, when something comes through a pipe
or file, from standard input (UTF-8). With `--output-format json` there is a line at the end
in the format of Claude Code, which the benchmark reads:

```json
{"type":"result","subtype":"success","is_error":false,"result":"...","num_turns":8,
 "duration_ms":24000,"session_id":"...","stop_reason":"done","agent":"unzensiert","version":"1.0.0",
 "usage":{"input_tokens":341,"output_tokens":326,"cache_read_input_tokens":11938},
 "modelUsage":{"local-coder":{"inputTokens":341,"outputTokens":326,"cacheReadInputTokens":11938,"costUSD":0}},
 "changed_files":["..."]}
```

`num_turns` counts the requests to the model, `stop_reason` is `done`, `stopped`, `loop` (the
same calls again and again), `limit` (`--max-turns`) or `error`. Notes like "server is
starting" go to the error output in a one-off run; standard output only contains the result.

## Built-in help against loops

- **Repetition:** when the model makes the same call with the same result for the third time
  while the changed files have the same content, a note appears in the result; at the sixth
  time the request ends (`maxRepeats`). A file that was changed and changed back counts as
  unchanged. Run times and memory addresses in results (`Ran 7 tests in 0.507s`, `0x1F2A`) do
  not count as a difference, whole numbers do.
- **Changes without effect:** an Edit with the same `old_string` and `new_string` or a Write
  with the content the file already has changes nothing. From the third such change in a
  request, whatever its arguments, a note appears in the result; at the sixth the request
  ends. The reason was a loop in the run `vergleich2`: the model wrote the same file four
  times unchanged and tried 16 edits without effect; because every change cleared the counter
  for repetitions, it ran until the time limit.
- **Refused calls:** see Rights.
- **Empty answers:** an answer with neither text nor a tool call does not end the request;
  the model thought but gave no result. It gets a note and goes on, at most
  `emptyAnswerNotes` (2) times per request. That happened in about one of 40 runs of the
  benchmark, also before the planning tools, and once ended a task after two rounds without
  a single change.
- **Cut-off calls:** if an answer ends at the token limit in the middle of a tool call, the
  model learns that it should write smaller pieces.
- **Maximum:** `maxToolRounds` rounds per request (200), `--max-turns` for one run.

## Settings (`config\unzensiert.json`)

| Key | Value | Purpose |
|---|---|---|
| `promptFile` | `unzensiert-prompt.md` | system prompt in `config\` |
| `projectFiles` | `AGENTS.md`, `CLAUDE.md` | instruction files of the project, the first existing one per folder |
| `permissionMode` | `ask` | rights mode at start |
| `readOnlyCommands`, `readOnlyGit` | list | commands that run without a question; their allowed options are in `config\readonly.json` |
| `fileCommands` | list | commands that count as file changes in `edits` |
| `interpreters`, `twoWordPrograms` | lists | what "always" remembers: for an interpreter the script or module, for these programs also the subcommand ([security.md](security.md#what-runs-without-a-question)) |
| `envDeny`, `envAllow` | regular expression, list | names of environment variables that are left out of the model's commands (tokens, secrets, passwords, keys), and names that stay although they match |
| `coAuthor` | `Unzensiert <359525642+Unzensiert-coder@users.noreply.github.com>` | `Co-authored-by:` line in commits of a session ([above](#commits-name-unzensiert-as-co-author)); empty = off |
| `addTools` | `TodoWrite`, `AskUserQuestion`, `PresentPlan`, `WebSearch`, `WebFetch` | tools of Unzensiert's own on top of `tools` in `config\agent.json` ([above](#tools)); remove a name to switch it off |
| `todoReminders` | `2` | how often per request open steps of the task list send the model back ([above](#planning-before-the-work)) |
| `emptyAnswerNotes` | `2` | how often per request an answer without text and without a tool call sends the model back ([above](#built-in-help-against-loops)) |
| `parallelToolCalls` | `false` | `true` asks the model to put calls that do not depend on each other into one answer ([above](#tools)); measured: fewer rounds, but neither faster nor better, so off |
| `web.searchEngine`, `web.duckduckgoUrl`, `web.searxngUrl` | `duckduckgo`, its page without scripts, empty | where `WebSearch` searches ([above](#research-on-the-web)) |
| `web.searchResults`, `web.pageChars` | `8`, `20000` | results per search, characters of a page per `WebFetch` call |
| `web.maxBytes`, `web.timeoutSeconds` | `5000000`, `20` | largest page that is read, time limit of a web request |
| `maxToolRounds` | `200` | rounds per request |
| `maxRepeats` | `3` | threshold for repetitions, changes without effect and refusals |
| `compactAt`, `keepRecentRounds`, `oldToolResultChars` | `0.80`, `6`, `1500` | context, see above |
| `editLines` | `false` | `true` offers `EditLines` next to `Edit`, for trying it with another model |
| `toolResultChars` | `30000` | longest output of a command |
| `readLines` | `2000` | lines `Read` returns without `limit` |
| `commandTimeoutSeconds`, `commandMaxSeconds` | `120`, `600` | time limits for commands |
| `maxOutputTokens` | `16384` | longest answer; never more than fits into the window |
| `showThinking` | `false` | show the thinking (in the session `/think`) |
| `historyFile` | `unzensiert-history.txt` | earlier input, in the install folder |

Model, short names, choice of `/model`, working rules, closing check, second look, tools and
`onExit` come from `config\agent.json` as with `claude-local`. A computer can change every
value in `config\machine.json` under `"unzensiert"`.

## Automatic updates

New versions appear as releases on GitHub (tag `vX.Y.Z`; the file `VERSION` in the project
names its own). At start in a terminal `unzensiert` looks at most every `checkHours` hours (24)
(`config\updates.json`, time limit `timeoutSeconds`). If a newer release is there, it gets the
program files – with git the tag, otherwise the ZIP of the tag, laid over the folder;
`config\machine.json` stays untouched –, installs the llama.cpp build of the new version
(`Install-LlamaCpp.ps1`), restarts the server when the build changed and no other session is
running, and restarts itself.

- **Switching off:** `unzensiert --updates off` (then noted in `config\machine.json` under
  `"updates"`), on again with `--updates on`. The installer asks once.
- **By hand:** `unzensiert --update` looks right away, even when automatic updates are off;
  the install line from the README does it as well.
- **Never touched** is a folder in which program files were changed by hand, and a full git
  clone that is not on a release (a development folder). Only copies of the installer
  (shallow clones, ZIP) and clones on a release tag are updated. The state of `main` between
  two releases never comes automatically.

## Limits

- **While the model works,** Unzensiert reads the keyboard for Esc; whatever you type during
  that time is lost.
- No subagents and no MCP servers: research happens in the same conversation, so long web
  pages and many files fill its context (old tool results are shortened, see Context).
- **The planning order** is a request in the system prompt; how well the local model asks,
  plans and keeps its list depends on the model.
- **The question frames** read single keys; they have been checked as output and with fixed
  answers, not yet by typing into a real window.
- **Images** only go to models with an image encoder (`mmproj`); otherwise Unzensiert replaces
  them by a note and asks again.
- **Without PSReadLine** (very old systems) there is only a simple input line without history
  and without Shift+Enter.
- **Wide characters** (Chinese script, emoji) count as one column in the terminal. In such
  lines replacing the raw line by the finished one can leave remnants.
- **Tables** are redrawn completely with every new row; if a table gets taller than the
  window, further rows only come below it.
- **Title and progress of the tab** exist only in Windows Terminal (the title also in other
  consoles); checked is the output, not the display in the window.

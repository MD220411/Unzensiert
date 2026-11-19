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
| `unzensiert --permission-mode edits` | rights mode `ask`, `edits` or `all` (the names of Claude Code work too) |
| `unzensiert --allowedTools "Bash(python:*)"` | allow these calls without a question, written as in Claude Code |
| `unzensiert --max-turns 30` | at most this many rounds with tool calls |
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
| Shift+Tab | switch the rights mode (`ask` → `edits` → `all`); text you had started goes into the list of earlier input |
| Alt+V | paste an image from the clipboard; the model sees it |
| `!command` | run a command yourself; the model sees command and output with the next message |
| `/help` | all commands |
| `/model [name or number]` | switch the model (entries of `picker` in `config\agent.json`) |
| `/mode [ask, edits, all]` | set the rights mode or move to the next one |
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
- **Status line** before every input: mood and model, context as a gauge, speed of the last
  answer, rights, graphics cards, folder and git, the time; whatever does not fit into the
  window is dropped. Your own message stands on a coloured bar after sending.
- **Activity line** while the model reads, thinks, writes a tool call, a command runs or the
  closing check works: what is happening, for how long, "Esc stops". Title and progress ring
  of the tab in Windows Terminal show the same, even when the window is in the background.
- **Answer** with Markdown (headings, lists, tasks, quotes, tables with aligned columns,
  links), wrapped at word boundaries; code blocks in a frame with the colours of their
  language. After thinking a line "∴ thought for 6.4 s · 365 tokens".
- **Tools** with sign and colour, tick or cross and duration; commands with the beginning and
  end of their output, changes as a diff with line numbers and marked characters.
- **Questions** in a frame, see Rights.
- After every request a line with duration, rounds, changed files, tokens and speed; at the
  end of the session a summary.

Colours and glyphs come from the active style (`config\style.json`, section `agent` of the
style file), the texts from `config\unzensiert-texts.json`.

## Rights

The guard decides first in every mode (`config\guard.json`, [security.md](security.md)):
what is blocked never runs, what is delicate always asks. After that the mode applies:

| Mode | Reading (Read, Glob, Grep, commands that only read) | Changing files in the project folder (Edit, EditLines, Write, file commands) | Other commands |
|---|---|---|---|
| `ask` (default) | without a question | question | question |
| `edits` | without a question | without a question | question |
| `all` | without a question | without a question | without a question |

- **Commands that only read** (`readOnlyCommands`, `readOnlyGit` in `config\unzensiert.json`:
  `ls`, `cat`, `grep`, `git status`, `git diff`, `Get-ChildItem` ...) also run as part of a
  longer line (`cd src && ls`). A redirection into a file (`>`) or a command substitution
  (`$(...)`) turns it into a question again.
- **Outside the project folder** Edit and Write ask in `edits` as well; only `all` lets them
  through without a question.
- **File commands** (`fileCommands`: `mkdir`, `rm`, `mv`, `cp`, `New-Item`, `Remove-Item` ...)
  count as file changes in `edits` when every target lies in the project folder. A target
  outside, in a variable or the project folder itself leads to a question.
- **The question** stands in a frame and shows the command in the colours of its shell, for
  Edit the change as a diff with line numbers, for Write the beginning of the file, plus the
  reason. Keys: `y` or Enter yes; `a` always (for this session: for commands the program the
  question names, for example `Bash(python:*)`, for files all changes); `n` or Esc no. (The
  German keys `j` and `i` still work.) If the guard asks, the frame is pink and there is no
  "always". After a no the model waits for your instruction.
- **Without a terminal** (`-p`) every question becomes a refusal with a reason for the model.
  After three refusals in one request it gets the note not to look for further detours; after
  nine the request ends.
- Command lines are split at `&&`, `||`, `;`, `|` and line breaks outside quotes; every piece
  must be allowed, `python -c "a; b"` stays one command.

## Tools

The model gets the tools from `tools` in `config\agent.json`, the same lean set as Claude Code
under `claude-local` (`Bash,Read,Edit,Write,Glob,Grep`; without Git Bash `PowerShell` instead
of `Bash`). Names and parameters are those of Claude Code, so the same guard checks both
agents. The setting `editLines` adds a tool of Unzensiert's own, `EditLines`; it is off,
because `local-coder` did not take it up (in a run of all eleven tasks it used it once in 89
edits). For the guard, the rights of a session and the closing check `EditLines` is an
`Edit`.

| Tool | What it does |
|---|---|
| `Bash` | command in Git Bash, `PowerShell` in Windows PowerShell 5.1; always in the project folder. The command goes into a script file (no trouble with quotes), runs without input, at most `commandTimeoutSeconds` (up to `commandMaxSeconds` when the model asks for more) and is ended with all its child processes. Long output keeps its beginning and end, because that is usually where the error is. Python writes UTF-8 (`PYTHONIOENCODING`); a line that is not UTF-8, such as the localised messages of a `powershell.exe` started from Git Bash, is read in the code page of the console. |
| `Read` | file with line numbers, parts with `offset`/`limit`; the model sees images as images |
| `Edit` | replace text; only after `Read` and only if the file has not changed since. The text must appear exactly once (or `replace_all`). Line endings (CR LF), encoding and byte order mark of the file stay as they were. If it does not find the text, it says whether only indentation or line breaks differ. |
| `EditLines` | only with `editLines`: replace whole lines by their numbers (`start_line` to `end_line`, as `Read` shows them) with `new_text`; the model quotes the first and the last of these lines as proof (`first_line`, `last_line`). If they do not match, nothing changes and the result names the real line and shows the place. The model writes only the new lines instead of copying the old ones into `old_string`. The result names the new numbers, because the lines below move. Same rules as `Edit`: only after `Read`, line endings and encoding stay. |
| `Write` | new file, or replace a file that was read completely. If the file already has exactly this content, it writes nothing and says so. |
| `Glob` | files by pattern (`**/*.py`, `src/*.{ts,tsx}`), newest first, without `.git`, `node_modules`, `__pycache__`, `.venv` |
| `Grep` | content by regular expression (.NET), output `path:line:text`, with `glob`, `ignore_case`, `files_only` |

## Closing check and second look

When the model wants to end an answer in which it changed files, the same closing check runs
as with `claude-local` (`scripts\hooks\Check-Stop.ps1`, `stopCheck` and `review` in
`config\agent.json`, [agent.md](agent.md)): check command of the project, reminder of test,
README and settings, after larger changes the second look. For that Unzensiert writes a short
transcript in the format the hook knows from Claude Code (requests and file changes,
`<session>.hook.jsonl`). If the check reports something, the model goes on; the messages name
the agent (`CLAUDE_LOCAL_AGENT=Unzensiert`). Esc also breaks off a long check.

## Context

The window is `ctx-size` of the model profile. After every answer Unzensiert knows the exact
token count from the server and only estimates what came since. When the conversation fills
`compactAt` (80 %) of the window, it first shortens old tool results (older than
`keepRecentRounds` rounds) to `oldToolResultChars` characters and drops the thinking of those
rounds; if that is not enough, the model summarises the conversation and keeps working
afterwards, with the last request word for word. If a request still does not fit, it
summarises and tries once more.

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
state, today's rules).

## System prompt

`config\unzensiert-prompt.md` with the facts of the session (date, Windows, folder, git,
shells), plus the instructions of the project (`projectFiles`: `AGENTS.md`, otherwise
`CLAUDE.md`, from the project folder and every folder above it, the nearest last) and the
working rules from `rulesFile` in `config\agent.json`. System prompt and tool descriptions
have about 8,900 characters together; the first request of a task measured 2,808 tokens.
Claude Code first sends about 26,000 tokens to the local server ([README](../README.md)). The
prompt says: answer in the language the user writes in.

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
- **Cut-off calls:** if an answer ends at the token limit in the middle of a tool call, the
  model learns that it should write smaller pieces.
- **Maximum:** `maxToolRounds` rounds per request (200), `--max-turns` for one run.

## Settings (`config\unzensiert.json`)

| Key | Value | Purpose |
|---|---|---|
| `promptFile` | `unzensiert-prompt.md` | system prompt in `config\` |
| `projectFiles` | `AGENTS.md`, `CLAUDE.md` | instruction files of the project, the first existing one per folder |
| `permissionMode` | `ask` | rights mode at start |
| `readOnlyCommands`, `readOnlyGit` | list | commands that run without a question |
| `fileCommands` | list | commands that count as file changes in `edits` |
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
- No subagents, no web search, no MCP servers: the tool set is the lean one of `claude-local`.
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

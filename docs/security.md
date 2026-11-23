# Protecting your own computer

The local model refuses nothing, not even an instruction hidden in a file or web page it has
read, and it makes mistakes. The protection therefore lies outside the model. It has a single
goal: to keep **this computer and your own data** from harm.

There are two things it explicitly does not do:

- It does not judge what the model is working on. There are no rules about content, topics
  or targets outside your own computer.
- It does not restrict normal work. Everything inside the project folder stays free:
  creating, changing and deleting files, starting programs and tests, installing packages,
  committing, pushing.

## The parts

| Part | Protects against | Where it is set |
|---|---|---|
| Key for the server | web pages in the browser and other programs that use the server | `config\server.json` |
| Trust in a folder | instructions, check commands and git programs a foreign folder brings along | asked at the start, kept in `<installRoot>\trust.json` |
| Guard before every tool call | destructive commands, access to credentials, paths to other computers | `config\guard.json` |
| What runs without a question | commands that only look as if they read | `config\readonly.json`, `config\unzensiert.json` |
| Files that run later by themselves | a file change that becomes a running program | `protectedFiles` in `config\guard.json` |
| The question before a call | saying yes to something you could not see | built in |
| Programs, git and environment | programs lying in the project folder, programs a repository names, keys in the environment | built in, `envDeny` in `config\unzensiert.json` |
| Git note at start | changes that cannot be undone | `config\agent.json` |
| Check script | configuration errors that silently switch the protection off | `scripts\Test-Setup.ps1` |

## Key for the server

`llama-server` only listens on `127.0.0.1`. Without a key, any web page open in the browser
could still talk to it: load models, send requests, read answers. The server reported this
itself at start (`no API key is set and CORS allows all origins`).

- **`requireApiKey`**: the server requires a key with every request. It is created at the
  first start (32 random bytes) and stored in `<installRoot>\run\api-key.txt`, outside the
  repository. The scripts, `unzensiert`, `claude-local` and Continue send it along.
- **`corsOrigins`** = `localhost`: a foreign web page may not read answers of the server.
- The key is passed through the environment, not the command line. That way it also applies
  to the model processes the server starts on their own ports, and it appears in no process
  list.

Measured: requests without a key get `401`, at the server and at the model process. `/health`
stays reachable without a key.

**Creating a new key:** stop the server, delete `api-key.txt`, `Start-Server.ps1`, then
`Install-Continue.ps1` (writes the key into the configuration of Continue).

## Trust in a folder

A folder you have cloned or unpacked can bring things along that an agent obeys or starts. Before
Unzensiert uses any of them it asks once, at the start, and lists them:

- **Instructions** (`AGENTS.md`, `CLAUDE.md`) from the repository down to the folder. Without your
  yes they are not part of what the model is told; it only learns that the files exist and that
  what they say is information. Folders above the repository (or above the folder, outside of one)
  do not count.
- **The check command** (`scripts\Check.ps1`, `Check.ps1`, with its steps in
  `config\check.json`). It also runs code the model has just written, so it is asked about once
  more before its first run: in this session, always in this project, or not.
- **What git would start or contact there:** programs the configuration of the repository or of
  one of its submodules names (`core.fsmonitor`, `filter.*`, `diff.*`, aliases with `!`, included
  files, hooks ...), objects on another computer, missing files it would fetch. It is read from the
  files, without starting git. Only settings known to be harmless pass without being listed; an
  ordinary clone has no others. Without your yes Unzensiert does not call git there, and the
  model's git commands ask.

`y` uses them, `v` shows them completely, `n` works without them in this session, Esc leaves. A
folder that brings none of these gets no question. What you confirmed is remembered together with
its checksum: when a file changes, by a `git pull` or by a command, the question comes again, and `v`
shows what has changed since. A change you approved in a session counts as confirmed. Projects made
with `New-Project.ps1` are confirmed from the start. A link that leads to another computer is never
opened.

Without a terminal (`-p`) nothing is confirmed; `--trust` uses everything in the folder for that
run. `claude-local` runs the check command only after the same yes, and asks at its start.

## Guard before every tool call

On Windows the commands of both agents run without a sandbox. Before every call of `Bash`,
`PowerShell`, `Read`, `Edit`, `Write`, `Glob` and `Grep` a guard therefore decides by fixed
rules from `config\guard.json`, and the model cannot talk it round. The rules are in
`scripts\hooks\GuardRules.ps1`, shared by both agents:

- **Unzensiert** checks in its own process, before a tool runs, first in every rights mode
  ([unzensiert.md](unzensiert.md)).
- **`claude-local`** gives Claude Code a hook (`PreToolUse`) that starts
  `scripts\hooks\Guard-Tool.ps1` as a process of its own for every call.

| Decision | Effect |
|---|---|
| none | The call runs. That is the normal case. |
| `ask` | You are asked and decide. In runs without a user (`-p`, benchmark) this counts as no. |
| `deny` | The call does not run. The model gets the reason. |

### What is blocked (`deny`)

| Rule | Content |
|---|---|
| `delete-system` | Recursive delete of a drive, of the user folder and its main folders, of the project and the install folder as a whole (`%CLAUDE_LOCAL_PROJECTS%`, `%CLAUDE_LOCAL_ROOT%`, see below), and everything in Windows and program folders; also with wildcards (`~/D*`), in loops, through `find -delete`, `xargs rm`, `Get-ChildItem \| Remove-Item`, `robocopy /mir` and `rsync --delete`, and with a variable nothing sets (`rm -rf "$DIR/"*` is `/*` then) |
| `disk-format` | Formatting, partitioning, raw overwriting of a drive |
| `boot-and-backups` | Deleting the boot configuration, shadow copies or backups, overwriting free space |

### When you are asked (`ask`)

| Rule | Content |
|---|---|
| `delete-project` | deleting the whole project folder or its `.git` |
| `delete-outside` | deleting outside the project folder (except in the temp folder), whole folders and single files; moving one of your main folders away; overwriting every file a listing found |
| `git-discard` | `git reset --hard`, `git clean -f`, `git checkout -- .`, `git branch -D` and similar |
| `git-force-push` | `git push --force`, `--delete`, `--mirror` (`--force-with-lease` is free) |
| `download-and-run` | downloading and running at once (`curl … \| sh`, `irm … \| iex`) |
| `registry-change` | changes to the registry |
| `security-off` | antivirus, firewall, user accounts, services |
| `autostart` | scheduled tasks, services, autostart entries, lasting environment variables, global git settings that start programs, extensions; writing files that programs read or start by themselves (`autostartPaths`: startup folder, profiles of the shells, `.gitconfig`, settings of VS Code ...) |
| `shutdown` | shutting down, restarting, signing out |
| `credential-tools`, `secret-paths`, `secret-files` | SSH keys, credentials of cloud services, GitHub and Claude, browser profiles, password databases (`secretPaths`, `secretFileNames`). Public keys (`*.pub`) are free. `Grep` and `Glob` leave such files out and say so. |
| `network-path` | Read, Glob, Grep, Edit or Write on another computer (`\\server\share`): looking such a path up already sends the name out, and Windows may sign in there |
| `odd-path` | paths with a special meaning (`\\?\`, data streams, `CON`); Unzensiert does not open them at all |
| `publish` | publishing in your name: releases, packages, settings of repositories (`git push` stays free) |
| `clipboard` | reading or changing the clipboard |
| `encoded-command`, `delete-by-code` | commands whose text is hidden in an encoding; code that deletes a folder of yours or of the system |
| `guard-files` | changes to the protection itself: its rules and scripts, the program folder, the install folder with its record of trust, the settings of Claude Code; starting Unzensiert with other rights |

What came up in a session is in `<installRoot>\logs\guard.log`.

**Folders of this computer.** `config\guard.json` names no fixed drives. It writes the
install folder and the projects folder as `%CLAUDE_LOCAL_ROOT%` and
`%CLAUDE_LOCAL_PROJECTS%`. `scripts\_common.ps1` sets both variables from the settings of the
computer, and the guard gets them through Claude Code; when you start it by hand,
`scripts\hooks\HookEnvironment.ps1` reads them itself. An entry with an unknown variable is
dropped, the other rules still apply.

### Changing the rules

Edit `config\guard.json`, then run `scripts\Test-Setup.ps1`. Applies from the next session.

- **A rule gets in the way:** set `decision` from `deny` to `ask` or remove the entry.
- **Another folder should be protected:** add it under `criticalPaths` (cannot be deleted as
  a whole) or `secretPaths` (access only after a question).
- **A new rule for commands:** an entry under `commandRules` with `id`, `decision`, `pattern`
  (regular expression, case-insensitive) and `reason`. Try it on a command that must match and
  on a similar one that must stay free.
- **Switching it off:** `"enabled": false`.

### Limits

- **No replacement for a sandbox.** The guard recognises commands by how they are written. It
  stops mistakes and direct attempts, not a command that is deliberately disguised (put together
  while it runs, hidden in a script that is first written and then started). Measured on
  2026-11-15: after a blocked command the model looked for another spelling on its own that
  was not blocked. In that case it was harmless; you cannot rely on that. Commands can only
  really be locked in with WSL2.
- **Delete targets in variables:** what the same command sets (`D=~/x; rm -rf "$D"`, loops) is
  followed, and a variable that nothing sets counts as empty. What comes out of another command
  (`$(mktemp -d)`) cannot be known; it stays free, otherwise normal work would be interrupted all
  the time.
- **A changed rule applies from the next session:** the rules are read once, so nothing that runs
  in a session can loosen them.
- **Cost:** with `claude-local` about 0.3 s per tool call (starting PowerShell, measured
  280 ms), with Unzensiert 2 to 7 ms (in its own process, measured with 2,441 commands of earlier
  sessions).
- **If the guard itself fails** (broken `guard.json`), you are asked at every call instead of
  everything running unchecked. `scripts\Test-Setup.ps1` shows the cause.
- **`.env` files in the project are not protected.** The model often needs them for the work,
  and it runs locally. If you want it otherwise, add `.env` under `secretFileNames`.
- The guard applies to `unzensiert` and `claude-local`. The normal `claude` is not affected.

## What runs without a question

Commands that only read run in every mode without a question. What counts is not a list of
forbidden things but the opposite: a line runs only when **all** of it is understood and every
option of it is listed in `config\readonly.json`. Bash lines are read by a small reader that
follows the rules of the shell, PowerShell lines by PowerShell's own parser. Variables (except
in `echo`), command substitution, output into files, commands in the background, groups, script
blocks that do more than compare, network paths, `cd` out of the project, git in another folder,
wildcards that could meet a link or a file whose name looks like an option, paths out of a pipe and
anything under `secretPaths` ask. A missing option costs one question and never lets something
through. To be asked more often, take names out of `readOnlyCommands` or `readOnlyGit`
(`config\unzensiert.json`, for one computer in `config\machine.json`).

The check was tried with random lines: thousands of them were put together from reading commands,
signs of the shell, options that write or start something and twisted paths, and every line it let
through was really run in a throw-away folder. Nothing changed that should not, and nothing read the
made-up secret next to it. The same for file commands in mode `edits`.

**"always"** means, for the rest of the session: for a command its program with the subcommand
(`git commit`, `npm test`); for an interpreter (`python`, `node`, `bash` ...) only the script or
module, and code on the command line only exactly this line; for file changes, also with `cp`,
`mv`, `rm` and the like, the files of the project. Output of an allowed program may go into files
of the project only. A line that is not understood is allowed only exactly as it is. After a `cd`
out of the project only rules you gave on the command line (`--allowedTools`) count. A `cd` that
could fail leaves the rest of the line in the old folder: both folders have to be in order then.

## Files that run later by themselves

Some files of a project are started or obeyed without anyone calling them: git hooks and
`.git\config`, tasks of editors (`.vscode`, `.idea`), `.github\workflows`, `AGENTS.md`,
`CLAUDE.md`, the check command, shortcuts, or a program named like one of the system (`git.cmd`,
`powershell.exe`). Changing one asks in the modes `ask` and `edits` every time, and "always" does
not cover it (`protectedFiles` in `config\guard.json`; take an entry out if it gets in your way).
All other files stay as free as the mode says. That includes build files and tests (`package.json`,
`conftest.py`, `build.rs`, `*.csproj` ...), because changing them is normal work; an open editor or a
running watcher may start them as soon as they change.

## The question before a call

- A command, an address and search terms are shown **completely**, over as many rows as needed. Of a
  long file or a very long command the question shows the beginning and says how many lines are
  missing; `v` shows everything. A command, a protected file and a file outside the project can
  only be allowed once everything was shown.
- The question names what "always" would allow, and where a path really leads if a link is on the
  way.
- Keys typed before the question appeared do not count. Questions of the guard need `y`; Enter is
  no yes there.
- **Nothing foreign steers the terminal:** escape sequences and invisible characters in commands,
  output, files, pages and answers become visible (`^[`, `<U+202E>`). Links can only be web
  addresses; when a label looks like another address, the real host stands behind it.

## Programs, git and the environment of commands

- **Programs by their full path.** Unzensiert starts Windows programs and git by their full path
  and switches the search in the current folder off for itself and for every command of the model
  (`NoDefaultCurrentDirectoryInExePath`); entries of `PATH` that start with a dot do not count for
  them.
- **git** runs with `core.fsmonitor=false` and `safe.bareRepository=explicit`, for Unzensiert
  itself and for the model's commands. Its own looks use no diff programs of the repository, leave
  submodules out and fetch nothing. Everything else a repository could start is part of the question
  about [trust](#trust-in-a-folder).
- **Environment:** variables that look like keys, tokens or passwords (`envDeny`) are left out of
  the environment of the model's commands. Names that must stay: `envAllow`. Commands you type
  yourself (`!`) keep everything.
- **One reading of a path:** guard, rights and tools use the same functions (one for Windows, one
  for Git Bash, whose drives `/c`, `/e` lie below one root). Links and junctions are followed before
  the decision, and a path that leads to another file when the tool runs is not opened.

## Web access

The tools `WebSearch` and `WebFetch` of Unzensiert
([unzensiert.md](unzensiert.md#research-on-the-web)) are the way the model looks things up on
the internet by itself; commands such as `curl` stay questions of the rights mode as before.
What that means for your data and your computer:

- **What leaves the computer:** the search terms (to DuckDuckGo, or to a SearXNG instance of
  your own) and the addresses of the pages the model reads, with the name and version of the
  program in the request. Nothing of the project goes along unless the model writes it into
  search terms or an address; the system prompt forbids secrets and personal data there.
- **You see it first:** in the modes `ask`, `edits` and `plan` every search and every page
  asks, and the question shows the terms or the address. "always" allows every search, or one
  host, for the rest of the session. In mode `all` they run without a question, like every
  command.
- **Hidden instructions:** a page can carry text written for a language model ("ignore your
  instructions and ..."). Parts a person does not see (hidden elements, size 0, invisible
  characters) are left out. Every page and every list of results reaches the model with the
  note that it is information, not instructions, but a local model can still fall for it.
  Such text cannot get past the guard; what remains is that the model might put data into a
  later search or address. That is why, outside mode `all`, every one of them asks.
- **Runs without a terminal** (`-p`, scripts, the benchmark) offer the web tools only in mode
  `all` or when `--allowedTools` names them; otherwise the model does not even get them.
- **Off:** remove `WebSearch` and `WebFetch` from `addTools` in `config\unzensiert.json` (for
  one computer in `config\machine.json` under `"unzensiert"`).

## Git note at start

`unzensiert` and `claude-local` report at start in a terminal when the folder is not a git
repository or has uncommitted changes (`gitCheck` in `config\agent.json`). With a commit
before the session, everything the model changes can be seen with `git diff` and undone with
`git checkout`. With redirected output (`-p` in scripts) the note does not appear.

## Check script

`scripts\Test-Setup.ps1` checks in a few seconds that the configuration files are valid and
consistent with each other, the scripts are readable (ASCII, syntax), model files and templates
are present and the guard answers. It needs no graphics card and ends with exit code 1 on an
error.

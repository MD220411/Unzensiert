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

## The four parts

| Part | Protects against | Where it is set |
|---|---|---|
| Key for the server | web pages in the browser and other programs that use the server | `config\server.json` |
| Guard before every tool call | destructive commands, access to credentials | `config\guard.json` |
| Git note at start | changes that cannot be undone | `config\agent.json` |
| Check scripts | configuration errors that silently switch the protection off | `scripts\Test-Setup.ps1`, `scripts\Test-Guard.ps1` |

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
| `delete-system` | Recursive delete of a drive, of the user folder and its main folders, of the project and the install folder as a whole (`%CLAUDE_LOCAL_PROJECTS%`, `%CLAUDE_LOCAL_ROOT%`, see below), and everything in Windows and program folders |
| `disk-format` | Formatting, partitioning, raw overwriting of a drive |
| `boot-and-backups` | Deleting the boot configuration, shadow copies or backups, overwriting free space |

### When you are asked (`ask`)

| Rule | Content |
|---|---|
| `delete-project` | deleting the whole project folder or its `.git` |
| `delete-outside` | recursive delete outside the project folder (except in the temp folder) |
| `git-discard` | `git reset --hard`, `git clean -f`, `git checkout -- .`, `git branch -D` and similar |
| `git-force-push` | `git push --force`, `--delete`, `--mirror` (`--force-with-lease` is free) |
| `download-and-run` | downloading and running at once (`curl … \| sh`, `irm … \| iex`) |
| `registry-change` | changes to the registry |
| `security-off` | antivirus, firewall, user accounts, services |
| `autostart` | scheduled tasks, services, autostart entries |
| `shutdown` | shutting down, restarting, signing out |
| `credential-tools`, `secret-paths`, `secret-files` | SSH keys, credentials of cloud services, GitHub and Claude, browser profiles, password databases (`secretPaths`, `secretFileNames`). Public keys (`*.pub`) are free. |
| `guard-files` | changes to `config\guard.json`, `config\machine.json`, the guard itself and the settings of Claude Code |

What came up in a session is in `<installRoot>\logs\guard.log`.

**Folders of this computer.** `config\guard.json` names no fixed drives. It writes the
install folder and the projects folder as `%CLAUDE_LOCAL_ROOT%` and
`%CLAUDE_LOCAL_PROJECTS%`. `scripts\_common.ps1` sets both variables from the settings of the
computer, and the guard gets them through Claude Code; when you start it by hand,
`scripts\hooks\HookEnvironment.ps1` reads them itself. An entry with an unknown variable is
dropped, the other rules still apply. `Test-Guard.ps1` sets fixed sample folders (`machine` in
`tests\guard-cases.json`) so the cases give the same result on every computer.

### Changing the rules

Edit `config\guard.json`, then run `scripts\Test-Guard.ps1`. Applies from the next session.

- **A rule gets in the way:** set `decision` from `deny` to `ask` or remove the entry.
- **Another folder should be protected:** add it under `criticalPaths` (cannot be deleted as
  a whole) or `secretPaths` (access only after a question).
- **A new rule for commands:** an entry under `commandRules` with `id`, `decision`, `pattern`
  (regular expression, case-insensitive) and `reason`. Add cases to `tests\guard-cases.json`
  as well: at least one that must match and a similar one that must stay free.
- **Switching it off:** `"enabled": false`.

`Test-Guard.ps1` hands every case from `tests\guard-cases.json` to the guard the way Claude
Code does. The first block of cases are normal working steps that must stay free; it keeps a
new rule from getting in the way of work.

### Limits

- **No replacement for a sandbox.** The guard recognises commands by how they are written. It
  stops mistakes and direct attempts, not a command that is deliberately disguised (built
  from variables, hidden in a script that is first written and then started). Measured on
  2026-11-15: after a blocked command the model looked for another spelling on its own that
  was not blocked. In that case it was harmless; you cannot rely on that. Commands can only
  really be locked in with WSL2 ([roadmap.md](roadmap.md), S6).
- **Delete targets in variables** (`rm -rf "$DIR"`) cannot be resolved by the guard; they stay
  free, otherwise normal work would be interrupted all the time.
- **Cost:** with `claude-local` about 0.3 s per tool call (starting PowerShell, measured
  280 ms), with Unzensiert 2.7 ms (in its own process, measured).
- **If the guard itself fails** (broken `guard.json`), you are asked at every call instead of
  everything running unchecked. `scripts\Test-Setup.ps1` shows the cause.
- **`.env` files in the project are not protected.** The model often needs them for the work,
  and it runs locally. If you want it otherwise, add `.env` under `secretFileNames`.
- The guard applies to `unzensiert` and `claude-local`. The normal `claude` is not affected.

## Git note at start

`unzensiert` and `claude-local` report at start in a terminal when the folder is not a git
repository or has uncommitted changes (`gitCheck` in `config\agent.json`). With a commit
before the session, everything the model changes can be seen with `git diff` and undone with
`git checkout`. With redirected output (`-p` in scripts) the note does not appear.

## Check scripts

| Script | Checks | Duration |
|---|---|---|
| `Test-Setup.ps1` | configuration files valid and consistent with each other, scripts readable (ASCII, syntax), model files and templates present, guard answers | a few seconds |
| `Test-Guard.ps1` | all cases from `tests\guard-cases.json` | about 25 s |

Neither needs a graphics card, and both end with exit code 1 on an error.

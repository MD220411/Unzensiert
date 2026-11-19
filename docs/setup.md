# Setup

Installation on a Windows computer, what the installer does, the values of the computer in
`config\machine.json` and which file sets what. The quick start for users is at the top of
the [README](../README.md).

## Requirements

- 64-bit Windows 10 (1809) or Windows 11.
- **Graphics card:** NVIDIA with a current driver is the tested path. With an older driver the
  installer takes the CUDA 12.4 package. AMD and Intel run through Vulkan:
  **experimental, not tested**. Without a graphics card the model runs on the processor, very
  slowly.
- **Main memory:** 16 GB from 26 GB of graphics memory, otherwise 32 GB, because parts of the
  model then lie in main memory. What counts is the installed memory (the memory modules);
  Windows reports a little less as usable, with 32 GB about 31.7 GB.
- **Disk space:** about 2 GB for llama.cpp and 17 to 22 GB per model.
- **Internet** for the installation. After that everything runs offline; only the automatic
  updates look on GitHub at most once a day (can be switched off).
- The installer brings Git for Windows after asking. Only the comparison command
  `claude-local` needs Claude Code; the installer offers it but does not suggest it. Only the
  benchmark needs Python, only Continue needs VS Code.

## Installing

| Way | Steps |
|---|---|
| One-liner | in PowerShell `irm https://raw.githubusercontent.com/MD220411/Unzensiert/main/install.ps1 \| iex` |
| ZIP | download "Source code (zip)" of the [latest release](https://github.com/MD220411/Unzensiert/releases/latest), unpack it, double-click `Install.cmd` |
| Git | `git clone https://github.com/MD220411/Unzensiert`, then `Install.cmd` |

The one-liner (`install.ps1`) puts the program into `%LOCALAPPDATA%\Programs\claude-local`.
It takes the newest release on GitHub (as long as there is none, the state of `main`): if Git
is there, it clones its tag, otherwise it downloads its ZIP. Then it starts
`scripts\Install.ps1`. It runs in the user's PowerShell session and never ends it.

If Windows reports "Windows protected your PC" for `Install.cmd`, that is because the file
came from the internet: "More info", then "Run anyway".

### What the installer does

`scripts\Install.ps1` works through seven steps and asks before it installs or downloads
anything. Enter always takes the suggestion.

| Step | Content |
|---|---|
| 1. Check the computer | Windows version, graphics cards (`nvidia-smi`, Windows display adapters), main memory |
| 2. Install folder | Suggestion: `claude-local` on the drive with the most room, on the system drive `%LOCALAPPDATA%\claude-local`. Never a whole drive, never in the program files folder. A folder chosen earlier stays. |
| 3. Git, Claude Code | Git for Windows through `winget`. Without Git the agent gets the tool PowerShell instead of Bash ([agent.md](agent.md)). Claude Code only for the comparison command `claude-local`, with Anthropic's official command (`irm https://claude.ai/install.ps1 \| iex`, in a process of its own); the question defaults to no, and `-Yes` does not install it either. |
| 4. llama.cpp | `Install-LlamaCpp.ps1`: package by graphics card (`packages` in `config\server.json`). Afterwards it checks with `llama-server --list-devices` whether llama.cpp sees the card; if not, it takes the next package ([backend.md](backend.md)). |
| 5. Model | Tier from `config\setups.json` by graphics memory (sum of all cards without integrated graphics) and installed main memory (sum of the memory modules), see below. Download with `Get-Model.ps1`. Then `Plan-Models.ps1 -Verify` computes the distribution over cards and main memory and checks it ([planner.md](planner.md)); if that fails, llama.cpp distributes the model itself (`--fit`). An existing plan stays. |
| 6. Commands, updates | `bin\` onto the user's PATH (`Install-Path.ps1`): commands `unzensiert` and `claude-local`. Once the question whether new releases come automatically (suggestion: yes), remembered in `machine.json` under `updates`; a later run does not ask again. |
| 7. Test | `Test-Setup.ps1` (only errors are shown), then `Test-Model.ps1 -NoLog` if the planner has not already tested the model |

| Switch | Effect |
|---|---|
| `-Plan` | only shows what would happen: installs, downloads and changes nothing (works on a copy of `machine.json`) |
| `-Yes` | takes every suggestion without a question; needed when nobody sits at the terminal |
| `-InstallRoot D:\ai` | this install folder |
| `-Model local-fast` | this model instead of the suggested one |

The installer is **repeatable**. A second run repairs: it skips what is already there,
resumes a broken download and leaves values in `machine.json` alone. If it stops, it says
why. Then simply start it again.

**Downloads.** `Get-Model.ps1` downloads the files of a profile as they are listed under
`download` in `config\models.json`: Hugging Face repository with a fixed state (commit), size
and SHA-256. A file is created as `<name>.part` and only gets its name once size and checksum
match. So a file under its proper name is always complete. `Get-Model.ps1 -List` shows all
profiles with size and state, `-Verify` checks existing files again.

### Hardware tiers

`config\setups.json` assigns a model and a context size to the graphics memory. The first
tier whose requirements the computer meets is suggested. How the model is then spread over
cards and main memory and which context really applies is computed by the planner for the
individual computer ([planner.md](planner.md)); the context size of the tier only applies when
it fails. The measurements below come from runs in which llama.cpp distributed the model
itself (`--fit`); the values with the planner are in [planner.md](planner.md).

| Graphics memory | Main memory | Model | Context | Measured on | Generation | Session start |
|---|---|---|---|---|---|---|
| from 26 GB | 16 GB | `local-coder` (Qwen 3.6 27B) | 128k | RTX 5070 Ti + RTX 3060 | 44 tokens/s (about 60 with its own split) | 32 s |
| from 22 GB | 16 GB | `local-coder` | 64k | both cards, limited to about 23 GB | 49 tokens/s | 30 s |
| from 15 GB | 32 GB | `local-coder`, partly in main memory | 64k | RTX 5070 Ti alone | 21 tokens/s | 46 s |
| from 11 GB | 32 GB | `local-fast` (Qwen 3.6 35B-A3B), partly in main memory | 64k | RTX 3060 alone | 62 tokens/s | 107 s |
| from 7 GB | 32 GB | `local-fast`, mostly in main memory | 64k | RTX 3060, 4 GB kept free | 57 tokens/s | 126 s |
| below | 32 GB | `local-fast` on the processor | 32k | Core i9-14900K | 26 tokens/s | 354 s |

Measured on 2026-11-17 on the development computer: llama.cpp saw only the chosen cards
(`CUDA_VISIBLE_DEVICES`), kept memory free where noted (`--fit-target`) and ran with the
general settings, without the fine-tuning of the development computer. "Generation" is the
speed from `Test-Model.ps1`, "session start" the time in which the model reads the roughly
26,000 tokens Claude Code sends first (Unzensiert sends about 2,800). All runs passed tool
calls and image input.

- **16 GB: `local-coder` instead of `local-fast`.** On the RTX 5070 Ti alone `local-fast`
  generates 97 tokens/s, `local-coder` only 21. But in the benchmark `local-coder` solved 14
  of 15 of the hard tasks, `local-fast` 3 of 15 (state before the closing check). Reliability
  comes first. The installer names
  `local-fast` as the alternative (`-Model local-fast`).
- **12 GB: `local-fast`.** On the RTX 3060 alone `local-coder` generates 11 tokens/s and
  needs 143 s for the session start; that is too sluggish for work.
- **Limits of the measurement.** One card alone stands for a computer with that card; a real
  card of the same size can be faster or slower (memory bandwidth, PCIe). The 22 GB and 8 GB
  tiers are simulated, not measured on such cards. This computer (128 GB) does not show the
  need for main memory reliably: Windows counts the mapped model file as well. The minimum
  values (16 GB, 32 GB with parts in main memory) are therefore estimates; the model process
  took 11 to 20 GB of private memory with parts moved out.

## Values of this computer: `config\machine.json`

The files in `config\` apply on every computer and are in the repository.
`config\machine.json` holds what only applies to this computer and is not in the repository
(`.gitignore`). The installer creates it. A section overrides the file of the same name:

| Section | overrides | Example |
|---|---|---|
| `server` | `server.json` | `installRoot`, `package` |
| `projects` | `projects.json` | `projectsRoot` |
| `agent` | `agent.json` | `model` (default model of this computer) |
| `modelDefaults` | `defaults` in `models.json` | `gpu-layers` |
| `models` | a profile in `models.json` | `args` (split, card, context), `file` |

Objects are merged key by key, `null` removes a key. Paths may contain `%VARIABLES%`. Then
there are the sections `plans` and `calibration` of the planner ([planner.md](planner.md)) and
`planner` (overrides `config\planner.json`). This is what the file looks like on a computer
with two cards (RTX 5070 Ti + RTX 3060, split computed):

```json
{
  "server": { "installRoot": "D:\\claude-local", "package": "win-cuda-13.5-x64" },
  "projects": { "projectsRoot": "D:\\Projects" },
  "agent": { "model": "local-coder" },
  "models": {
    "local-coder": { "args": { "ctx-size": 131072, "fit": "off", "gpu-layers": 66,
                               "device": "CUDA1,CUDA0", "tensor-split": "29,37",
                               "mmproj-offload": false } },
    "qwen2.5-coder-1.5b-base": { "file": "qwen2.5-coder-1.5b-base-Q4_K_M.gguf", "args": { "device": "CUDA1" } }
  },
  "plans": { "local-coder": { "ctx": 131072, "predictedTokensPerSecond": 28, "measuredTokensPerSecond": 70.7 } },
  "calibration": { "local-coder": { "speed": { "Host": 19.89, "CUDA0": 1.38, "CUDA1": 3.57 } } }
}
```

Changing it by hand is allowed. The installer keeps the values and only adds missing ones;
`Plan-Models.ps1` overwrites the options it sets itself. Afterwards
`scripts\Restart-Server.ps1`, then `scripts\Test-Setup.ps1`. The guard asks before the model
changes the file ([security.md](security.md)).

## Updating

- **Automatically:** at start `unzensiert` looks at most once a day whether a newer release is
  on GitHub, and brings it in (program files, plus the llama.cpp build of the new version;
  `machine.json` stays). Only published releases count, never the working state of `main`.
  Switch off: `unzensiert --updates off`, back on: `--updates on`; the installer asks once.
  Look right now: `unzensiert --update`. Details: [unzensiert.md](unzensiert.md), section
  "Automatic updates".
- **Run the one-liner** again. It gets the newest release (with git the tag, otherwise the ZIP
  over the folder, `machine.json` stays; as long as there is no release, the state of `main`)
  and starts the installer, which only adds what is new. If files in the program folder were
  changed by hand, it does not update and says so.
- **Git clone for development:** `git pull`, then `Install.cmd`. A full clone that is not on a
  release is never updated automatically.
- **New llama.cpp version:** `build` in `config\server.json`, then `Install-LlamaCpp.ps1`
  ([backend.md](backend.md)).

## Uninstalling

`Uninstall.cmd` or `scripts\Uninstall.ps1` asks before every part:

1. Stop the server.
2. Take `bin\` off the PATH.
3. Take back the look ([style.md](style.md)), if it is installed.
4. In the install folder delete only what the installer created: llama.cpp folders
   (`b<number>` with `llama-server.exe`), the files of the profiles from `models.json`, `run`,
   `logs`, `downloads`, `bench-work`, the saved conversations of Unzensiert (`sessions`) and
   its input history. Other files stay and with them the folder. `-KeepModels` keeps the
   models.
5. Delete `config\machine.json`.

Claude Code, Git for Windows and the settings of Continue stay. The script shows at the end
how to remove them. Delete the program folder by hand afterwards.

## Which file sets what

| File | Content | Description |
|---|---|---|
| `config\server.json` | llama-server: version, packages per graphics card, address, limits | [backend.md](backend.md) |
| `config\models.json` | model profiles: file, download, context, sampling | [models.md](models.md) |
| `config\setups.json` | hardware tiers: which model for how much graphics memory | above |
| `config\machine.json` | values of this computer, from the installer, not in the repository | above |
| `config\planner.json` | planner: reserves, context sizes, tolerance | [planner.md](planner.md) |
| `config\templates\*.jinja` | adapted chat templates | [models.md](models.md) |
| `config\agent.json` | both agents: default model, short names, choice, rules, closing check, tools | [agent.md](agent.md) |
| `config\unzensiert.json` | Unzensiert: rights, context, time limits | [unzensiert.md](unzensiert.md) |
| `config\unzensiert-texts.json` | texts of the terminal of Unzensiert | [style.md](style.md) |
| `config\updates.json` | automatic updates from the releases on GitHub | above |
| `config\coding-rules.md` | working rules for the local model | [agent.md](agent.md) |
| `config\style.json`, `config\styles\` | the look of terminal, shell, Unzensiert and Claude Code | [style.md](style.md) |
| `config\continue.config.yaml` | Continue: chat and autocomplete models | below |
| `config\guard.json` | guard rules for tool calls of the local model | [security.md](security.md) |

## Continue (chat and autocomplete in the editor)

`scripts\Install-Continue.ps1` installs the extension, copies `config\continue.config.yaml` to
`%USERPROFILE%\.continue\config.yaml` (an existing, different file is backed up), enters the
key of the server on the way and checks that every model named is a profile. After a new key,
run the script again. `Get-Model.ps1 -Model qwen2.5-coder-1.5b-base` downloads the
autocomplete model.

- Chat uses `local-coder` or `local-fast` through the OpenAI-compatible interface.
- Autocomplete uses `qwen2.5-coder-1.5b-base` through the interface `/completion`. On the
  development computer the model lies alone on the RTX 3060 (`machine.json`) and fits next to
  each of the large models.
- The server must be running (`scripts\Start-Server.ps1`).
- As of 2026-11-15: the interfaces are checked with direct requests, the operation in VS Code
  itself not yet after the switch to llama.cpp, not with the key of the server either. If
  Continue reports error 401, it does not send the key ([backend.md](backend.md),
  troubleshooting).

## What is left of Ollama

Nothing on the development computer. Until 2026-11-14 the project ran on Ollama; on the same
day Ollama was uninstalled:

- The program, its model folder (64 GB) and `%USERPROFILE%\.ollama` are removed, as is
  Ollama's autostart entry.
- The user variables `OLLAMA_*` and `LLAMA_ARG_TENSOR_SPLIT` are deleted.
- The GGUF files taken over at the time lay as hard links in the model folder of llama.cpp and
  were kept.

The old scripts and settings are in the git history before the first public version (up to
commit `fbb8c80`, not published).

## Autostart

`llama-server` does not start with Windows. There is no service, no autostart entry and no
scheduled task. The server only runs once `unzensiert`, `claude-local` or
`scripts\Start-Server.ps1` starts it, and until `scripts\Stop-Server.ps1` or signing out.

## Troubleshooting

Backend: [backend.md](backend.md). Agent: [unzensiert.md](unzensiert.md),
[agent.md](agent.md). Beyond that:

| Symptom | Cause and remedy |
|---|---|
| `Install stopped: ...` | The message names the reason. Fixed? Start the installer again; it continues there. |
| `No llama.cpp package could use the graphics card` | Driver too old or card not supported. Update the driver, start the installer again. |
| `Not enough disk space` | Choose another install folder (`-InstallRoot`) or make room. |
| `unzensiert` or `claude-local` is not found | Open a new terminal (the PATH only applies there). Otherwise run `scripts\Install-Path.ps1`. |
| `no model is installed yet` | Start the installer again or `scripts\Get-Model.ps1 -Model <name>`. |
| The agent does not edit files, only writes text | The model cannot do tool calls. `Test-Model.ps1 -Model <name>` must show `tool calling: OK`. |
| The agent forgets the beginning of the session | Context full. New session or `/clear`. |
| A script stops with garbled characters in its messages | A `.ps1` file contains non-ASCII characters. Windows PowerShell 5.1 reads files without a BOM as ANSI. |

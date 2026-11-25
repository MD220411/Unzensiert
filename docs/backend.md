# Backend: llama.cpp

The server that loads the models onto the graphics cards and answers requests is
`llama-server` from [llama.cpp](https://github.com/ggml-org/llama.cpp).

## Operating it

Each one is called with `powershell -ExecutionPolicy Bypass -File scripts\<name>`.

| Script | Effect |
|---|---|
| `Start-Server.ps1` | Starts the server if it is not running and shows the model profiles. |
| `Stop-Server.ps1` | Stops the server and all loaded models. Frees the GPU memory. |
| `Restart-Server.ps1` | Both, one after the other. Needed after every change to `config\server.json` or `config\models.json`. |
| `Test-Model.ps1 [-Model <name>]` | Loads a profile and checks speed, tool calls, image input and GPU memory. |
| `Test-Setup.ps1` | Checks configuration and scripts without loading a model. |

`unzensiert` and `claude-local` start the server themselves when it is not running. Continue
needs it running; after a restart of the computer run `Start-Server.ps1`, `unzensiert` or
`claude-local` once.

Models are loaded with the first request (the uncensored one in about 8 s from the file
cache, up to 50 s from disk).

## When the GPU memory is freed

| Occasion | Effect | Setting |
|---|---|---|
| The last session of `claude-local` ends | The models of the agent are unloaded, the server keeps running. Measured: 15.6 and 10.4 GB in use (128k context), afterwards 7 and 0 MiB. | `onExit` in `config\agent.json` ([agent.md](agent.md)) |
| 30 minutes without a request to a model | The model sleeps: its process stays but frees the memory (measured: 226 and 105 MiB left). The next request wakes it in about 7 s; the context cache is empty then, the conversation is read in once more. | `sleep-idle-seconds` in `config\models.json` |
| Another model needs the room | The server unloads unused models until the new one fits. | `memoryMarginMiB`, `modelsMax` |
| `Stop-Server.ps1` | Everything freed. | |

Earlier conversations are kept in main memory, not on the cards: when one comes back, the
server takes its state from there instead of reading it in again. The planner sets how much
main memory that cache may take per model (`cache-ram`, [planner.md](planner.md#the-computation)).

Without a loaded model the server itself uses no GPU memory. The idle limit is the safety
net for cases in which `claude-local` cannot clean up: window closed, crash, or the model was
loaded by Continue. Status queries (`/health`, `/models`, `/props`) do not count as requests.

## Settings (`config\server.json`)

Values of this computer are in `config\machine.json` (section `server`) and override the
file ([setup.md](setup.md)).

| Key | Value | Purpose |
|---|---|---|
| `installRoot` | `%LOCALAPPDATA%\claude-local` | Folder for programs, models, logs and generated files. The installer chooses it and writes it into `machine.json`. |
| `build` | `b12433` | Version of llama.cpp (tag of the GitHub releases). The programs are in `<installRoot>\<build>\`. |
| `package` | `auto` | Variant of the download. `auto` chooses by graphics card, see `packages`; the package that worked is then noted in `machine.json`. |
| `packages` | `nvidia`: `win-cuda-13.5-x64`, `nvidiaFallback`: `win-cuda-12.4-x64`, `other`: `win-vulkan-x64`, `cpu`: `win-cpu-x64` | What `auto` means. With an NVIDIA card CUDA 13.5 first; if llama.cpp sees no card with it (driver too old), CUDA 12.4. AMD and Intel: Vulkan (experimental, untested). Without a card: CPU. |
| `modelsDir` | empty = `<installRoot>\models` | Folder of the GGUF files |
| `devices` | empty = every usable card | The graphics cards llama.cpp may use, by their ids of `llama-server --list-devices` (`CUDA0`, `Vulkan1`). A computer chooses them with `/gpu` in `unzensiert` (in `machine.json`); every model is then started with these cards only, and the planner spreads the models over them ([planner.md](planner.md#choosing-the-cards)). |
| `host`, `port` | `127.0.0.1`, `8080` | Address of the server. Reachable only from this computer. |
| `requireApiKey` | `true` | The server requires a key with every request. It is created at the first start and stored in `<installRoot>\run\api-key.txt` ([security.md](security.md)). |
| `corsOrigins` | `localhost` | Which web pages may read answers of the server in the browser. Leave empty for the llama.cpp default (all). |
| `modelsMax` | `3` | At most this many models loaded at the same time |
| `memoryMarginMiB` | `512` | Before loading a model the server unloads unused models until the new one fits and this much memory stays free per card |
| `startTimeoutSeconds` | `60` | How long the scripts wait for the server to start |
| `loadTimeoutSeconds` | `300` | How long test and benchmark wait for a model to load |

If the address is different here, change it in `config\continue.config.yaml` as well.

## How the server is started

`scripts\lib\Server.ps1` does three things in `Start-Server`:

1. It creates the file `<installRoot>\run\models.ini` (the format of
   `llama-server --models-preset`) from `config\models.json` and the values of this computer
   (`machine.json`). Profiles whose GGUF file has not been downloaded are left out; that is
   normal, not every computer has every model (`Get-Model.ps1 -List`).
2. It removes every `LLAMA_ARG_*` variable from its own environment. `llama-server` also
   reads its options from such variables; a forgotten variable (like
   `LLAMA_ARG_TENSOR_SPLIT` from the Ollama days) would otherwise silently affect every
   model.
3. It starts `llama-server` in router mode:
   `--models-preset <ini> --models-max <n> --models-memory-margin <MiB> --no-ui --offline
   --cors-origins <value>`. The key reaches the process through the variable
   `LLAMA_API_KEY`, not through the command line; that way the model processes require it
   as well.

The router starts a child process `llama-server` with the options of the profile for every
requested model. `Stop-Server` only stops processes from `installRoot`; a `llama-server` of
another program stays untouched.

The server does not start with Windows, see [setup.md](setup.md).

## Interfaces

| Interface | Address | Used by |
|---|---|---|
| OpenAI-compatible | `http://127.0.0.1:8080/v1/chat/completions` | Unzensiert, Continue (chat), test and benchmark scripts |
| Anthropic-compatible | `http://127.0.0.1:8080/v1/messages` | Claude Code (`claude-local`) |
| llama.cpp's own | `http://127.0.0.1:8080/completion` | Continue (autocomplete) |
| Management | `GET /models`, `POST /models/load`, `POST /models/unload`, `GET /health` | scripts |

Every request names a profile in the field `model` and sends the key of the server along
(`Authorization: Bearer <key>` or `x-api-key`). Only `/health` answers without a key. The scripts,
`unzensiert` and `claude-local` send the key only when `llama-server.exe` of the install folder
listens on the port (`Get-ServerRequestKey` in `scripts\lib\Server.ps1`,
[security.md](security.md#key-for-the-server)). By hand:

```
$key = Get-Content <installRoot>\run\api-key.txt
curl.exe -H "Authorization: Bearer $key" http://127.0.0.1:8080/models
```

## Updating llama.cpp

1. Choose a newer build on <https://github.com/ggml-org/llama.cpp/releases>.
2. Change the value `build` in `config\server.json`, and add an entry for it under `sha256`: the
   SHA-256 of every file a package of `packages` needs (`llama-<build>-bin-<package>.zip`, for
   CUDA also `cudart-llama-bin-<package>.zip`), from the release page (`gh api
   repos/ggml-org/llama.cpp/releases/tags/<build>` lists them as `digest`). Without an entry
   nothing is downloaded, and `Test-Setup.ps1` reports the missing ones.
3. Run `scripts\Install-LlamaCpp.ps1`. It downloads the archives of the package over https only,
   checks them against `sha256` (GitHub must name the same), unpacks them into `<installRoot>\<build>\`
   (emptied first, so that no leftover of another package loads a second backend) and
   checks with `--list-devices` that llama.cpp sees the graphics card. Otherwise it tries
   the next package from `packages`. `-Package win-vulkan-x64` forces another package.
4. `scripts\Restart-Server.ps1`, then `scripts\Test-Model.ps1`.
5. To go back, set `build` to the old value again; the old folder stays until you
   delete it.

## Troubleshooting

The log of the server and of all model processes is `<installRoot>\logs\server.log`.

| Symptom | Cause and remedy |
|---|---|
| `llama-server not found` | Run `scripts\Install-LlamaCpp.ps1`. |
| The server does not start within 60 s | Read the log. Often: port in use (change `port`) or the wrong `package` for the driver. |
| A profile is missing from the model list | Its GGUF file has not been downloaded on this computer: `scripts\Get-Model.ps1 -Model <profile>`, then `Restart-Server.ps1`. See [models.md](models.md). |
| A model does not load (state stays `loading` or falls back to `unloaded`) | Search the log for `error`. Usually the GPU memory is not enough: close other programs or lower `ctx-size`. |
| Error `model limit reached, try again later` | The new model only fits when another one is unloaded, and that one is answering a request right now. A model in use is never unloaded. Wait, or end the other session. Check: `curl "http://127.0.0.1:8080/slots?model=<profile>"` (`is_processing`). |
| Much slower than expected | Parts of the model are in main memory (intended on small cards, see [setup.md](setup.md), hardware tiers). `Test-Model.ps1` shows the GPU memory; lower `ctx-size` for the profile in `machine.json`, or with several cards let the planner compute the split ([planner.md](planner.md)). |
| A long conversation takes a minute before the answer starts, after another session used the same model | The cache of earlier conversations in main memory was too small, the conversation is read in again (log: `selected slot by LRU`, then `prompt processing` over the whole conversation). Run `scripts\Plan-Models.ps1`, it sets `cache-ram` by the main memory of this computer ([planner.md](planner.md#the-computation)). |
| Error `System message must be at the beginning` | The model uses its built-in chat template. Give the profile a `chat-template-file`, see [models.md](models.md). |
| Error 500 `A tool message must follow an assistant or tool message`, Claude Code repeats the request several times | As above: built-in chat template without the block "agent fix". Happens as soon as a tool result arrives together with text, for example after reading an image. [models.md](models.md), section "Chat template". |
| The model does not recognise images or reads them wrong | Run `Test-Model.ps1`. `image input: not configured`: the profile has no `mmproj`. A warning at start: the `mmproj` file is missing from `modelsDir`. Small images read wrong: raise `image-min-tokens`. |
| GPU memory stays in use after `exit` | Another session of `claude-local` is still running (the last line names the reason), `onExit` is set to `keep`, or the window was closed. Then the idle limit takes over; free it at once with `Stop-Server.ps1`. |
| Continue reports connection errors | The server is not running: `scripts\Start-Server.ps1`. |
| Error 401 `Invalid API Key` | The caller sends no key or an old one. Continue: `scripts\Install-Continue.ps1` and restart VS Code. Own calls: send the key from `<installRoot>\run\api-key.txt`, see "Interfaces". If a server from before a change of the key is still running: `Restart-Server.ps1`. |
| A script fails on a configuration file | `scripts\Test-Setup.ps1` names the file and the place that does not fit. |
| The answer never ends, the model keeps calling tools | The model writes an open `<tool_call>` at the end, and the grammar of llama.cpp forces a complete call out of it. Affected qwen3-coder 30B; use another model. |

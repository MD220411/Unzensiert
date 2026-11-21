# Models and profiles

A **profile** is an entry in `config\models.json`: a name, a GGUF file and the options with
which `llama-server` loads it. Unzensiert, Claude Code, Continue and the scripts always ask
for models by their profile name.

## Existing profiles

| Profile | Role | Model | Download | Purpose |
|---|---|---|---|---|
| `local-coder` | agent | Qwen 3.6 27B, uncensored (Heretic v2), Q4_K_M with MTP | 17.2 GB | default model of the agent from 15 GB of graphics memory |
| `local-fast` | agent | Qwen 3.6 35B-A3B (mixture of experts), uncensored (Heretic), Q4_K_M with MTP | 22.7 GB | more tokens per second, less reliable on harder tasks; default model below 15 GB of graphics memory, because it is much faster there (measured, [setup.md](setup.md)) |
| `local-qwen38` | agent | Qwen 3.8 27B, uncensored (Heretic), Q4_K_M with MTP | 17.6 GB | default model until 2026-11-14, reviewer of the second look; needs its own chat template |
| `qwen2.5-coder-1.5b-base` | autocomplete | Qwen 2.5 Coder 1.5B base model | 1.6 GB | tab completion in Continue |
| `local-coder-nvfp4` | compare | `local-coder` with NVFP4 weights (4-bit floating point, computed in hardware by Blackwell cards) | 16.9 GB | only for the benchmark; on the development computer slower than Q4_K_M (measured) |
| `local-next` | compare | Qwen 3.8 Flash-Next (mixture of experts, 125B parameters plus a 51B n-gram table, about 6B active per token), uncensored (abliterated), IQ3_XXS, MTP head in a file of its own | 76.1 GB + 2.2 GB | a large model in graphics and main memory together (about 80 GB); only for the benchmark |
| `local-coder-q5`, `-rb2048`, `-rb512`, `-rb0` | compare | variants of `local-coder` | | only for the benchmark |

The installer decides which model a computer gets by its graphics memory
([setup.md](setup.md), hardware tiers). `scripts\Get-Model.ps1 -Model <profile>` downloads
more; `-List` shows what is installed.

## Structure of `config\models.json`

```json
{
  "defaults": { "flash-attn": "on", "cache-type-k": "q8_0", ... },
  "models": {
    "local-coder": {
      "description": "...",
      "role": "agent",
      "file": "qwen3.6-27b-heretic-v2-Q4_K_M-mtp.gguf",
      "download": {
        "repo": "llmfan46/Qwen3.6-27B-uncensored-heretic-v2-Native-MTP-Preserved-GGUF",
        "revision": "a6b6a6d9385fe7850644e56bfdc93a04a6cb2ee8",
        "files": [ { "name": "<file in the model folder>", "source": "<file in the repository>", "size": 17211797600, "sha256": "..." } ]
      },
      "args": { "mmproj": "qwen3.6-27b-mmproj-BF16.gguf", "ctx-size": 131072, ... }
    }
  }
}
```

- `role`: `agent` (for the agents, offered by the installer), `autocomplete` (Continue) or
  `compare` (benchmark only).
- `file` is the file name in the model folder (`<installRoot>\models`).
- `download` says where `Get-Model.ps1` gets the file and the image encoder from: repository
  on Hugging Face, fixed state (commit), per file its name in the repository, size and
  SHA-256. A profile name instead of the object means: the same files as that profile.
  `Test-Setup.ps1` checks that the entry names all files of the profile.
- `args` are options of `llama-server` without the leading dashes. The complete list is shown
  by `<installRoot>\<build>\llama-server.exe --help`.
- `defaults` apply to every profile; a value in `args` overrides them, `null` removes it.
- **No split across particular cards in this file.** The planner computes the distribution
  over the cards of a computer (`tensor-split`, `device`, `mmproj-device`, `gpu-layers`,
  `n-cpu-moe`, context; with weights in main memory also `ubatch-size` and `batch-size`, with
  a draft model of its own `spec-draft-device`) and writes it into `config\machine.json` under
  `models.<profile>.args` ([planner.md](planner.md)). Without a plan llama.cpp distributes the
  model itself (`--fit`, the default).

After every change: `scripts\Restart-Server.ps1`, then `scripts\Test-Model.ps1 -Model <name>`.

### Options used here

The values of `gpu-layers`, `tensor-split`, `device`, `mmproj-device` and `n-cpu-moe` are
computed by the planner per computer ([planner.md](planner.md)); the examples below come from
the development computer (RTX 5070 Ti + RTX 3060).

| Option | Value | Purpose |
|---|---|---|
| `gpu-layers` | `999` (development computer) | All layers onto the graphics cards. Without it `--fit` decides. |
| `flash-attn` | `on` | Faster attention, less memory |
| `cache-type-k`, `cache-type-v` | `q8_0` | Context cache in 8 bits: about half the memory for the context |
| `parallel` | `1` | One request at a time. Every further slot shares the context window. |
| `jinja` | `true` | Evaluate the chat template of the model; needed for tool calls |
| `ctx-size` | `131072` | Context window in tokens. At least 64k for the agents; with 128k the long task no longer breaks off. In a session of `claude-local` the smallest window of the profiles in the model choice counts. |
| `tensor-split` | `70,30` (development computer) | Share of the model for RTX 5070 Ti and RTX 3060. The more lies on the faster card, the faster. Without it `--fit` distributes. |
| `device` | `CUDA1` (development computer) | Put the model on one card only (`CUDA0` = 5070 Ti, `CUDA1` = 3060; list: `llama-server.exe --list-devices`) |
| `spec-type` | `draft-mtp` | Speculative decoding with the MTP head of the model, see below |
| `spec-draft-n-max` | `4` | How many tokens the model drafts ahead |
| `spec-draft-model` | file name in `modelsDir` (`local-next`) | MTP head in a file of its own instead of inside the model, looked for in the model folder like `mmproj`; the planner puts it on the fastest card (`spec-draft-device`, `spec-draft-ngl`) |
| `ubatch-size`, `batch-size` | `2048` (only when weights stay in main memory) | Tokens read per step. Computed by the planner: the cards fetch weights that lie in main memory once per step, so larger steps read the prompt faster ([planner.md](planner.md)) |
| `lazy-mode` | `on` (`local-next`) | The n-gram table of Qwen 3.8 Flash-Next stays on the disk and is read row by row when needed (as the profile describes it; not checked here) |
| `chat-template-file` | `templates\qwen3.6-agent.jinja`, `templates\qwen3.8-agent.jinja` | Own chat template, path relative to `config\`, see below |
| `mmproj` | file name in `modelsDir` | Image encoder of the model, see "Images" |
| `mmproj-device` | `CUDA1` (development computer) | Card for the image encoder. On the RTX 3060 it frees 1.2 GB on the RTX 5070 Ti, images stay just as fast (measured). |
| `image-min-tokens` | `256` | Minimum number of tokens per image; small images are scaled up for it, see "Images" |
| `sleep-idle-seconds` | `1800` (in `defaults`) | After 30 minutes without a request the model frees its GPU memory and loads again with the next request ([backend.md](backend.md)) |
| `reasoning-effort` | `medium` | Thinking effort the chat template gives the model |
| `temp`, `top-k`, `top-p`, `min-p`, `repeat-penalty` | per model | Sampling values the maker of the model recommends |

## MTP (multi-token prediction)

The Qwen models used here contain an MTP head: the model drafts several tokens ahead and
checks them in one step. With `spec-type = draft-mtp` llama.cpp uses that as speculative
decoding, which about doubles the speed. It requires a GGUF file **with** MTP head (often
`-mtp` in the file name, stated on the model card). Some models bring the head as a file of
its own (`local-next`); it is named in `spec-draft-model`.

`Test-Model.ps1` shows whether MTP runs in the line `speed` (`MTP on, 76 % of drafted tokens
accepted`). Models without an MTP head do not get the option.

Measured and left out: n-gram drafts in addition to MTP (`spec-type ngram-mod,draft-mtp`), which
guess passages the model copies from the conversation, and longer MTP drafts (6 tokens with
`spec-draft-p-min`); in agent work neither was faster than MTP with 4 tokens (measured
2026-11-18).

## Images

The three agent models can read images (screenshots, sketches, photos of error messages).
For that every model needs its image encoder, a second GGUF file (`mmproj`) that is named in
the profile under `args` and lies next to the model in `modelsDir`. If the file is missing,
the model loads without image input and `Start-Server.ps1` warns.

There are two ways in a session: paste an image into the input (Alt+V, or drag a file into
the terminal) or name its path; then the model reads the file with the tool `Read`.

`image-min-tokens = 256` scales small images up. Measured with `local-coder` on 2026-11-14:
of twelve images with a large four-digit number (448 × 224 pixels) the model read 5 right
without the option (about 100 tokens per image), all 12 with 256 and with 1024. It read eight
screenshots of a terminal (1600 × 900, font 11 pt, about 1400 tokens per image) right in all
three settings. 256 costs about 300 tokens of context for small images, 1024 about 1100.
llama.cpp recommends 1024 only for tasks in which the model is to give positions in the
image.

`Test-Model.ps1` checks the image input in the line `image input`.

## Chat template

Every GGUF file brings a chat template that translates messages into the text format of the
model. The built-in templates are not enough for work with the agents; all three agent
models therefore use a template from `config\templates\`. Each is the template from the GGUF
file with the changes described at the top of the file.

| Template | Profiles | Changes |
|---|---|---|
| `qwen3.6-agent.jinja` | `local-coder`, `local-fast` | order of the tool results |
| `qwen3.8-agent.jinja` | `local-qwen38` | order of the tool results, later system messages |

**Order of the tool results (block "agent fix").** Claude Code often sends the result of a
tool together with text in one message (reminders, notes). `llama-server` turns that into
"text, then tool result", the wrong order (`tools/server/server-chat.cpp`, also in the current
state of llama.cpp). The built-in template of Qwen 3.6 then stops with `A tool message must
follow an assistant or tool message.`, Claude Code shows error 500 and tries again several
times. The template of Qwen 3.8 does not stop but shows the model the note before the result
of its own call. The block at the start of the templates puts the tool results directly
behind the answer that asked for them. The error showed up with images, but it affected every
tool.

**Later system messages (Qwen 3.8 only).** The built-in template stops with `System message
must be at the beginning.` as soon as a system message is not in first place. Claude Code
sends such messages in the middle of the conversation. The template outputs them as a system
block of their own.

For a new model:

1. Load the model and read its built-in template:
   `curl http://127.0.0.1:8080/props?model=<profile>` (field `chat_template`).
2. If it is the same as that of an existing model, enter that model's template. Otherwise
   save it as `config\templates\<name>.jinja`, put the block "agent fix" from an existing
   template behind the check `No messages provided` and describe the change at the top of the
   file.
3. Enter `"chat-template-file": "templates\\<name>.jinja"` in the profile.
4. `Test-Model.ps1` must show `image input: OK`; the test sends exactly the form the built-in
   templates fail on.

## Adding a new model

1. **Create a profile.** Add an entry under `models` in `config\models.json`; `local-coder` is
   the pattern for Qwen models with MTP. At least `role`, `file`, `download` and `ctx-size`.
   For `download` read the state and the checksums from the API, do not copy them:
   `curl.exe https://huggingface.co/api/models/<repo>` (field `sha`) and
   `.../api/models/<repo>/tree/main` (per file `size` and `lfs.oid` = SHA-256). For images add
   the `mmproj` file to `download.files` and to `args`. Check the chat template, see above.
2. **Download:** `scripts\Get-Model.ps1 -Model <name>`. A file that is already on the disk is
   put into the model folder instead by `scripts\Add-Model.ps1 -Path D:\dl\model.gguf -Name <file>`
   (on the same drive as a hard link without extra space).
3. **Start and check:** `scripts\Restart-Server.ps1`, then `scripts\Test-Model.ps1 -Model <name>`.
   The test must show `tool calling: OK`, otherwise the agent cannot edit files, and
   `image input: OK`, otherwise it fails on images and on tool results with text attached.
4. **Try it with the agent:** `unzensiert --model <name>` or `claude-local -Model <name>`.
5. **Add it to the choice (optional):** enter it in `config\agent.json` under `picker` and
   `aliases` ([agent.md](agent.md)).

If the GPU memory is not enough, a smaller `ctx-size` or a new plan helps
([planner.md](planner.md)), both for your own computer in `config\machine.json`. The test shows
the memory in use per card; a few hundred MiB per card should stay free.

## Removing a model

Delete the entry from `config\models.json` (and from `agent.json`, `setups.json`,
`continue.config.yaml`, where it appears), restart the server, then delete the
file in the model folder. To remove it on one computer only: delete the file; the profile is
then missing from the model list of the server and from `/model`.

## Origin of the files

The sources are in the field `download` of each profile: repository, fixed state and SHA-256
per file, read from the Hugging Face API on 2026-11-17. The files on the development computer
match: the sizes of all model files are byte-identical, the SHA-256 of the three image
encoders (`mmproj`) was recomputed on 2026-11-17 and matches. Exception: the autocomplete file
of the development computer (Q4_K_M, from Ollama) has no byte-identical source; new computers
get the Q8_0 file from `ggml-org`, the development computer keeps its own through
`machine.json`.

The model folder of the development computer holds a file without a profile:
`gpt-oss-20b-MXFP4.gguf` (a hard link to the file of another project, takes no extra space).
The file of qwen3-coder 30B (formerly `local-fast`) was deleted on 2026-11-14. Both were
dropped after the benchmark: gpt-oss 20B passed only one of three runs of the harder task, and
qwen3-coder 30B often did not stop at the end of its answer.

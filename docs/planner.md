# Planner: spreading models over GPUs and main memory

The planner (`scripts\Plan-Models.ps1`, computation in `scripts\lib\Planner.ps1`) works out
for every computer how a model is spread fastest over its graphics cards and main memory:
how many layers on which card, in which order, which experts into main memory, where the
image encoder goes and which context size. The installer calls it after the download; the
result is stored in `config\machine.json`.

Without the planner llama.cpp distributes the model itself (`--fit`). That makes sure
everything fits, but not that it is fast: on the development computer (RTX 5070 Ti +
RTX 3060) `local-coder` produced 44 tokens/s that way, about 60 with the split of 70/30 found
by hand, and 66 to 71 with the plan (measured, see below).

## The computation

**Memory.** For a given distribution llama.cpp itself estimates how many MiB of weights,
context and compute buffers end up on each device (`llama-fit-params --fit-print on`, about
half a second per call). The planner adds what this estimate does not know about and
compares with the free memory llama.cpp reports:

| Addition | Value | Origin |
|---|---|---|
| Reserve per card | 1024 MiB | CUDA context of the server (650 MiB measured, 540 of which are already missing from the reported free memory) and room for the measuring processes the router briefly starts for the other models after every start (about 550 MiB each). With 512 MiB a model crashed at that moment. |
| MTP drafting | 1408 MiB on the card with the last layers | own context and buffers of the draft, measured 1375 MiB at 128k |
| Image encoder | file size + 256 MiB | on the card that still has enough room afterwards, otherwise on the processor |

**Speed.** For every generated token every weight is read once, in a mixture-of-experts model
only the active experts (8 of 256). The time per token is therefore roughly

    t = Σ over all devices (MiB read on the device × microseconds per MiB of the device)

The MiB read follow from the estimate of llama.cpp: weights on the device, minus the inactive
experts and the token embedding that main memory only holds. The planner measures the
microseconds per MiB once per model (**calibration**, about half a minute) with
`llama-bench`: once on the processor only, then once per card "this card filled first". Each
run is an equation whose unknowns are the microseconds per MiB of the cards; a small linear
system of equations gives them. That needs no table of card data and works for AMD and Intel
as well.

On the development computer this gave 1.38 µs/MiB for the RTX 5070 Ti (≈ 760 GB/s),
3.57 µs/MiB for the RTX 3060 (≈ 294 GB/s) and 19.9 µs/MiB for main memory. The ratio of the
cards (2.6) matches that of the manufacturer figures (896 to 360 GB/s, 2.5). Two splits that
only move weights between the cards gave the same difference (2.16 and 2.10 µs per MiB
moved).

**Search.** For every context size (128k, 96k, 64k, 32k):

1. The fastest card is filled first, as far as it fits (binary search over the number of
   layers, each probe with the estimate of llama.cpp), then the next one. The fastest card
   comes last in the device list (`--device`): that way it gets the output layer and the MTP
   layer, which are read several times per token during drafting.
2. If not everything fits on the cards, with a mixture-of-experts model experts move to main
   memory first (`--n-cpu-moe`, as few as needed): from there only the few active ones are
   read per token. Only after that, and right away with dense models, do the first layers
   stay in main memory.
3. The time per token is predicted with the formula above.

The largest context size from `minCtx` (64k) up is chosen whose time is at most
`speedTolerance` (15 %) above the fastest one. More context is worth some speed: in the
benchmark the task `longcontext` only passed with 128k.

**One context per session.** `claude-local` sets the window of a session to the smallest model
of the `/model` choice, so a switch does not make any model overflow. The planner therefore
computes the default model first; the other models of the choice get at least its context if
it fits for them. Otherwise `local-fast` would have got 64k on the development computer
(200.8 instead of 171.2 tok/s) and every session with `local-coder` would have shrunk to 64k.

**Cache of earlier conversations.** Every model process of `llama-server` keeps the state of
earlier conversations in main memory, so that a conversation that comes back does not have
to be read in again (`--cache-ram`, 8 GiB by default). With the Qwen 3.6 models one entry is
3.4 to 7.4 GB (they keep up to 32 checkpoints of their recurrent state per conversation), so
the default holds a single conversation: when two conversations take turns, for example two
sessions or a session and a side request, each one is read in completely every time
(measured on the development computer: prompts of 53,000 to 60,000 tokens, 63 to 74 s each).
The planner therefore gives every model what is left of the main memory after `ramReserveGiB`
and the model's own share there, divided by `modelsMax` of `config\server.json` (that many
models can be loaded at once), at most `cacheRamMaxGiB`. If that is not more than the 8 GiB of
llama.cpp, the option stays out. On the development computer (128 GB) that is 32 GiB per
model. The limit is not reserved: the cache only takes memory for conversations that are
actually kept. Measured with two conversations of about 33,000 tokens and 37 requests each,
taking turns: with 8 GiB each one was read in completely when it came back (35 to 36 s), with
32 GiB only the new 300 tokens (0.8 s).

**Result.** In `config\machine.json` under `models.<profile>.args`: `ctx-size`,
`gpu-layers`, `device` (slowest card first), `tensor-split` (units per card; the output layer
counts as one unit), `n-cpu-moe`, `mmproj-device` or `mmproj-offload: false`, `cache-ram`, and
`fit: off` so that llama.cpp moves nothing any more. Next to it `plans.<profile>` (prediction,
measured speed) and `calibration.<profile>` (the measuring runs).

## Using it

```
powershell -ExecutionPolicy Bypass -File scripts\Plan-Models.ps1            # all downloaded agent models
powershell -ExecutionPolicy Bypass -File scripts\Plan-Models.ps1 -Verify    # then load and test
... -Model local-fast    only this profile
... -Recalibrate         measure again (otherwise only when the cards have changed)
... -Show                show the saved plans
```

The planner stops the server so the cards are empty. Plan again after changing the graphics
card or when other programs permanently take graphics memory. `-Verify` loads every model and
checks it with `Test-Model.ps1`; if it does not load or the model process crashes under a
request, it plans again with 1 GB more reserve per card (at most twice) and remembers the
reserve in `machine.json` (`planner.reserveMiB`).

## Measured

All runs on 2026-11-17 on the development computer, with `Test-Model.ps1` (speed with MTP
drafting; it varies by a few percent with the hit rate of the draft), plus reading 26,177
tokens. Tool calls and image input OK in all runs. Raw values: `logs\model-tests.log`.

| Cards | Model, context | `--fit` | By hand | Planner |
|---|---|---|---|---|
| RTX 5070 Ti + RTX 3060 | `local-coder`, 128k | 44 tok/s | 58.5 / 61.8 | **65.7 / 70.7** |
| RTX 5070 Ti alone | `local-coder`, 64k | 20.9 tok/s, prompt 572/s | | **21.8**, prompt 591/s |
| RTX 5070 Ti alone | `local-fast`, 64k | 97.1 tok/s, prompt 775/s | | **105.7**, prompt 844/s |
| RTX 3060 alone | `local-fast`, 64k | 62.2 tok/s, prompt 244/s | | **65.0**, prompt 260/s |

On the development computer, both cards, free choice (current state in `machine.json`):
`local-coder` 128k at 66.9 tok/s, `local-qwen38` 128k at 70.5 tok/s (by hand before about 55
to 58), `local-fast` 128k at 171.2 tok/s (by hand before 83 to 140; with 64k it would be
200.8, see "One context per session"). The setting made by hand is kept in
`<installRoot>\run\machine.json.vor-planer`.

Without constraints the planner chose: on the RTX 5070 Ti alone 96k for `local-coder`
(18.7 tok/s), on the RTX 3060 alone 128k for `local-fast` (58.2 tok/s), on the RTX 3060 with
4 GB kept free (≈ an 8 GB card) 128k (53.6 tok/s).

The gain on two cards comes mostly from the order: output and MTP layer on the fast card. The
setting of 70/30 by hand with the reverse order did not load at all any more; only the
computation finds the fitting split (38 and 37 layers on the RTX 5070 Ti). On one card the
plan gains 4 to 9 %: image encoder on the processor, exactly as many experts moved out as
needed.

The values the planner predicts (without MTP, about 28 tok/s for the plan on two cards) are
lower than the ones measured with MTP; only the ratios between the variants matter for the
choice.

## Limits

- **Windows moves memory out silently.** When a card is full, the NVIDIA driver moves memory
  into main memory (sysmem fallback), without an error, only slower. The amount in use then
  sits at a fixed limit (RTX 5070 Ti: 15.58 GB). The reserve is meant to prevent that;
  `Plan-Models.ps1 -Verify` only checks that the model runs, not whether it is moved out.
- **Mixture of experts calibrates badly.** On the processor such a model is limited by
  computing rather than reading; the card values from its runs are unreliable (measured:
  0.55 µs/MiB for the RTX 3060, impossible). That does not matter for the choice on one card;
  with several cards the planner takes the card values from the calibration of a dense model
  on the same cards, if there is one. It replaces implausible values (≤ 0 or slower than main
  memory) by a twelfth of the main memory value and reports that.
- **Prediction too pessimistic with experts moved out.** For `local-fast` the planner
  predicted 32 % less speed with the experts of one layer in main memory than without; about
  15 % was measured. The main memory value of a MoE model comes from a run on the processor
  only, where it is limited by computing. The choice can therefore lean towards a small
  context.
- **The formula knows no context depth.** In a long conversation every token also reads the
  context cache; the prediction applies to a short conversation.
- **Untested:** real computers with other cards, AMD and Intel through Vulkan (the
  computation is the same, but `Get-GpuMemory` shows nothing there), more than two cards.

## Settings (`config\planner.json`)

| Key | Value | Purpose |
|---|---|---|
| `reserveMiB` | `1024` | kept free per card, see above |
| `mtpReserveMiB` | `1408` | addition for MTP drafting on the card with the last layers |
| `ramReserveGiB` | `6` | main memory for Windows and other programs |
| `cacheRamMaxGiB` | `32` | upper limit of the cache of earlier conversations per model, see "Cache of earlier conversations" |
| `mmprojExtraMiB` | `256` | compute buffer of the image encoder |
| `ctxCandidates` | `131072, 98304, 65536, 32768` | context sizes tried |
| `minCtx` | `65536` | smaller only when nothing else fits |
| `speedTolerance` | `0.15` | this much slower a larger context may be |
| `bench` | `tokens 32, repetitions 2, cpuTokens 12` | measuring runs of the calibration |

A computer can override single values in `config\machine.json` under `planner`. After a
change: `scripts\Plan-Models.ps1 -Verify`.

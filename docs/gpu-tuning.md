# GPU split

> **As of 2026-11-14:** The measurements in this document are from 2026-11-13 and ran
> through Ollama. The findings about the hardware still hold. What changed is the setting:
> since the switch to llama.cpp every model has its own split (`tensor-split` in
> `config\models.json`, today computed by the planner, [planner.md](planner.md)). The
> restriction from the section "Why 65:35 and not 70:30" no longer exists. The files and
> scripts named there (`config\ollama.env.json`, `Set-OllamaEnv.ps1`,
> `Measure-GpuSetups.ps1`) only exist in the git history.

Assessment of the measurements in [gpu-setups.md](gpu-setups.md), measured on 2026-11-13 with
`scripts\Measure-GpuSetups.ps1`. Hardware: RTX 5070 Ti (16 GB, PCIe 5.0 x16) and RTX 3060
(12 GB, **PCIe 4.0 x4**).

## In short

- **PCIe x4 does not slow things down** as long as the model is split by layers (Ollama's
  default). Per token only an intermediate value of a few KB crosses the bus.
- **The bottleneck is the 3060 itself:** its memory and compute are clearly weaker. Every
  layer on the 3060 costs more time than on the 5070 Ti.
- **So put as much as possible on the 5070 Ti.** The setting was
  `LLAMA_ARG_TENSOR_SPLIT=65,35` in `config\ollama.env.json`.
- **The biggest lever is not the split, though, but MTP** (speculative decoding): it doubles
  the speed of the Qwen 3.8 models. See [model-choice.md](model-choice.md).

## Evidence: PCIe x4 costs nothing

A small model (`qwen3:8b`) that fits on either card alone:

| Setup | Generation speed | Prompt reading |
|---|---|---|
| 5070 Ti only | 144 tok/s | 5926 tok/s |
| 3060 only | 54 tok/s | 1285 tok/s |
| split across both (2.5 / 2.1 GB) | **86 tok/s** | **3388 tok/s** |

If the bus slowed things down, the split result would be below what follows from the two
single values. Adding up the time per token from the shares of the two cards gives about
80 tok/s for generation and about 2200 tok/s for prompt reading. More was measured,
because both cards partly work at the same time on the prompt.

## Evidence: the 3060 slows things down

The 3060 is 2.6 times slower than the 5070 Ti at generating and 4.6 times slower at reading
prompts. Every layer that moves to the 5070 Ti makes the model faster:

| Model | Default | 65:35 | 70:30 | 75:25 |
|---|---|---|---|---|
| `unc-blackfrost` (`local-coder` until Nov 14, removed) | 47.5 tok/s | 54.9 | 59.9 | does not fit |
| `unc-heretic` (`local-coder` since Nov 14) | 49.9 tok/s | 54.9 | 60.1 | does not fit |
| `unc-coletti` (removed) | 49.3 tok/s | 53.3 | 62.0 | does not fit |
| `qwen3.8:27b` | 60.4 tok/s | 60.1 | 63.4 | 66.7 ¹ |
| `local-fast` (`qwen3-coder:30b`) | 141 tok/s | 137 | does not fit | does not fit |
| `local-legacy` (the first `local-coder`, removed) | 25.1 tok/s | 25.5 | does not fit | 27.7 ¹ |

The gain is larger for prompt reading: for `local-fast` 3242 → 3851 tok/s (+19 %) with
65:35, for the MTP models about 830 → 925 (65:35) or 1045 tok/s (70:30).

¹ Only runs because Ollama moves the image encoder into main memory after the first failure.
Not reliable.

## Why 65:35 and not 70:30

The split applied to all models at once: Ollama passes the variable to every llama-server it
starts. At 70:30 `local-fast` no longer fits on the 5070 Ti and would stop with an error,
also in the chat of Continue. 65:35 is the largest split with which all models load. The MTP
models give away about 9 % of speed compared with 70:30.

Whoever does not need `local-fast` can set `LLAMA_ARG_TENSOR_SPLIT` to `70,30`
(`config\ollama.env.json`, then `Set-OllamaEnv.ps1` and `Restart-Ollama.ps1`).

The autocomplete model is not affected: Ollama puts it on a single card (the 3060) with
`--split-mode none`. Checked: both models also fit completely on the GPUs at 65:35 at the
same time, in both loading orders.

## What does not help

| Setup | Result |
|---|---|
| `row` (every layer on both cards) | Does not start with any model in this Ollama version. |
| `tensor` (both cards compute every layer) | Here PCIe x4 really slows things down: prompt reading halved, `local-fast` generates 32 % slower. |
| `LLAMA_ARG_FIT_TARGET` (reserve on the 3060) | llama.cpp then moves layers into main memory instead of onto the 5070 Ti. Up to three times slower. |
| `num_batch 1024` | For `local-fast` prompt +16 %, generation −7 %. No difference for the other models. |

## Pitfalls the measurement uncovered

- **Models without a profile load with 262k context.** The Ollama app passes its context
  setting (262144) to the server. A model without `num_ctx` in its profile takes so much
  memory that llama.cpp puts layers into main memory: `qwen3.8:27b` dropped from 60 to
  14 tok/s this way. That is why every model in use gets a profile in `modelfiles\`.
- **Ollama reports "100 % GPU" even when layers are in main memory.** The reliable figure is
  the line `offloaded X/Y layers` in the server log. The measuring script evaluates it.
- **Changing the request options reloads the model.** If a program sends a different
  `num_ctx` than the profile, Ollama reloads the model with that value, without a message.

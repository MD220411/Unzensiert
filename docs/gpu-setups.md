# GPU-Aufteilung: Messwerte

**Historischer Stand (Ollama, 2026-11-13).** Erzeugt von `scripts\Measure-GpuSetups.ps1`, das mit dem Umbau auf
llama.cpp am 2026-11-14 entfernt wurde (Git-Historie vor der ersten öffentlichen Version, bis `fbb8c80`). Die Werte bleiben als Beleg für [gpu-tuning.md](gpu-tuning.md).
Stand: 2026-11-13 20:52. Rohdaten: `logs\gpu-setups\results.jsonl`.
Die Setups stehen in `config\gpu-setups.json`. Bewertung: [gpu-tuning.md](gpu-tuning.md).

Spalten: **Gewichte** = Modellgewichte in GB je Geraet laut llama.cpp (CPU = im Arbeitsspeicher;
bei den Einzel-GPU-Tests heisst die einzige sichtbare Karte immer 5070Ti, siehe Setup-Name).
Bei `tensor` meldet llama.cpp die Gewichte nicht je Karte (`Meta()`). **Tempo leer** = Antwort-Tempo ohne Kontext (Median),
**Tempo 17k** = Antwort-Tempo nach einem Prompt von etwa 17.000 Tokens, **Prompt** = Verarbeitung
dieses Prompts. **MTP** = spekulatives Dekodieren aktiv. **Schichten** = Schichten auf der GPU laut
llama.cpp (die GPU-Angabe von Ollama zeigt auch dann 100 %, wenn Schichten im Arbeitsspeicher liegen).
Alle Werte stammen aus der letzten Ladung im Lauf (ein Nachladen mit anderen Optionen wird erkannt).

## `local-coder`

| Setup | Gewichte (GB) | Schichten | Tempo leer | Tempo 17k | Prompt | MTP | Laden | Hinweis |
|---|---|---|---|---|---|---|---|---|
| standard | 5070Ti 10,0 / 3060 7,4 / CPU 0,7 | 65/65 | 25.1 Tok./s | 23.1 Tok./s | 1273.1 Tok./s | nein | 6.4 s | Ollama/llama.cpp decide (layer split by free memory) |
| split-65-35 | 5070Ti 10,5 / 3060 6,9 / CPU 0,7 | 65/65 | 25.5 Tok./s | 23.4 Tok./s | 1375.5 Tok./s | nein | 6.3 s | more layers on the 5070 Ti |
| split-70-30 | - | - | - | - | - | - | - | FEHLER: Der Remoteserver hat einen Fehler zurückgegeben: (500) Interner Serverfehler. |
| split-75-25 | 5070Ti 11,9 / 3060 5,5 / CPU 0,7 | 65/65 | 27.7 Tok./s | 25.7 Tok./s | 1898.1 Tok./s | nein | 7 s | probably too much for 16 GB |
| row | - | - | - | - | - | - | - | FEHLER: Der Remoteserver hat einen Fehler zurückgegeben: (500) Interner Serverfehler. |
| tensor | CPU 0,7 / Meta() 8,7 | 65/65 | 26.4 Tok./s | 23.5 Tok./s | 641.3 Tok./s | nein | 7.4 s | tensor parallel: heavy PCIe traffic |
| batch-1024 | 5070Ti 10,0 / 3060 7,4 / CPU 0,7 | 65/65 | 24.8 Tok./s | 22.8 Tok./s | 1247.1 Tok./s | nein | 9.3 s | larger prompt batches (default 512) |
| fit-1g-4g | 5070Ti 11,4 / 3060 5,2 / CPU 1,4 | 63/65 | 18.8 Tok./s | 18.2 Tok./s | 1109.3 Tok./s | nein | 7.4 s | llama.cpp fit keeps 4 GB free on the 3060, adapts per model |
| fit-512-6g | 5070Ti 11,5 / 3060 3,3 / CPU 3,1 | 57/65 | 7.9 Tok./s | 8.2 Tok./s | 1160.6 Tok./s | nein | 12 s | llama.cpp fit keeps 6 GB free on the 3060, adapts per model |

## `local-fast`

| Setup | Gewichte (GB) | Schichten | Tempo leer | Tempo 17k | Prompt | MTP | Laden | Hinweis |
|---|---|---|---|---|---|---|---|---|
| standard | 5070Ti 10,1 / 3060 7,0 / CPU 0,2 | 49/49 | 141.3 Tok./s | 59.6 Tok./s | 3242.3 Tok./s | nein | 4.6 s | Ollama/llama.cpp decide (layer split by free memory) |
| split-65-35 | 5070Ti 11,2 / 3060 6,0 / CPU 0,2 | 49/49 | 137 Tok./s | 64.6 Tok./s | 3850.7 Tok./s | nein | 5.4 s | more layers on the 5070 Ti |
| split-70-30 | - | - | - | - | - | - | - | FEHLER: Der Remoteserver hat einen Fehler zurückgegeben: (500) Interner Serverfehler. |
| split-75-25 | - | - | - | - | - | - | - | FEHLER: Der Remoteserver hat einen Fehler zurückgegeben: (500) Interner Serverfehler. |
| row | - | - | - | - | - | - | - | FEHLER: Der Remoteserver hat einen Fehler zurückgegeben: (500) Interner Serverfehler. |
| tensor | CPU 0,2 / Meta() 8,6 | 49/49 | 95.8 Tok./s | 51.7 Tok./s | 1718.8 Tok./s | nein | 11.9 s | tensor parallel: heavy PCIe traffic |
| batch-1024 | 5070Ti 10,1 / 3060 7,0 / CPU 0,2 | 49/49 | 131.7 Tok./s | 59.6 Tok./s | 3758.9 Tok./s | nein | 6.7 s | larger prompt batches (default 512) |
| fit-1g-4g | 5070Ti 11,2 / 3060 5,7 / CPU 0,4 | 49/49 | 133.5 Tok./s | 65.4 Tok./s | 2725.3 Tok./s | nein | 9.9 s | llama.cpp fit keeps 4 GB free on the 3060, adapts per model |
| fit-512-6g | 5070Ti 11,6 / 3060 3,7 / CPU 1,9 | 49/49 | 82.2 Tok./s | 57.4 Tok./s | 2370.7 Tok./s | nein | 10.3 s | llama.cpp fit keeps 6 GB free on the 3060, adapts per model |

## `qwen3.8:27b`

| Setup | Gewichte (GB) | Schichten | Tempo leer | Tempo 17k | Prompt | MTP | Laden | Hinweis |
|---|---|---|---|---|---|---|---|---|
| standard | 5070Ti 9,2 / 3060 5,8 / CPU 0,7 | 66/66 | 60.4 Tok./s | 57.7 Tok./s | 953.3 Tok./s | ja | 6.7 s | Ollama/llama.cpp decide (layer split by free memory) |
| split-65-35 | 5070Ti 9,2 / 3060 5,8 / CPU 0,7 | 66/66 | 60.1 Tok./s | 52.6 Tok./s | 950.9 Tok./s | ja | 5.4 s | more layers on the 5070 Ti |
| split-70-30 | 5070Ti 10,0 / 3060 4,9 / CPU 0,7 | 66/66 | 63.4 Tok./s | 54.1 Tok./s | 1027 Tok./s | ja | 7 s | more layers on the 5070 Ti |
| split-75-25 | 5070Ti 10,7 / 3060 4,3 / CPU 0,7 | 66/66 | 66.7 Tok./s | 61.4 Tok./s | 1112.1 Tok./s | ja | 6.8 s | probably too much for 16 GB |
| row | - | - | - | - | - | - | - | FEHLER: Der Remoteserver hat einen Fehler zurückgegeben: (500) Interner Serverfehler. |
| tensor | CPU 0,7 / Meta() 7,5 | 66/66 | 56.7 Tok./s | 47.6 Tok./s | 611.2 Tok./s | ja | 11 s | tensor parallel: heavy PCIe traffic |
| batch-1024 | 5070Ti 9,6 / 3060 5,4 / CPU 0,7 | 66/66 | 60.3 Tok./s | 50.6 Tok./s | 983.1 Tok./s | ja | 9.3 s | larger prompt batches (default 512) |
| fit-1g-4g | 5070Ti 7,7 / 3060 7,1 / CPU 0,9 | 65/66 | 54 Tok./s | 49.2 Tok./s | 651.9 Tok./s | ja | 10.4 s | llama.cpp fit keeps 4 GB free on the 3060, adapts per model |
| fit-512-6g | 5070Ti 11,2 / 3060 2,4 / CPU 2,1 | 60/66 | 38.2 Tok./s | 35.2 Tok./s | 1274.9 Tok./s | ja | 10.4 s | llama.cpp fit keeps 6 GB free on the 3060, adapts per model |

## `qwen3:8b`

| Setup | Gewichte (GB) | Schichten | Tempo leer | Tempo 17k | Prompt | MTP | Laden | Hinweis |
|---|---|---|---|---|---|---|---|---|
| small-5070ti | 5070Ti 4,5 / CPU 0,3 | 37/37 | 143.7 Tok./s | 98.9 Tok./s | 5925.5 Tok./s | nein | 11.6 s | small model on the 5070 Ti only |
| small-3060 | 5070Ti 4,5 / CPU 0,3 | 37/37 | 54.4 Tok./s | 30 Tok./s | 1285.1 Tok./s | nein | 2.3 s | small model on the 3060 only |
| small-spread | 5070Ti 2,5 / 3060 2,1 / CPU 0,3 | 37/37 | 85.6 Tok./s | 54.1 Tok./s | 3388.1 Tok./s | nein | 2.4 s | small model split across both GPUs (layer) |
| small-spread-row | - | - | - | - | - | - | - | FEHLER: Der Remoteserver hat einen Fehler zurückgegeben: (500) Interner Serverfehler. |

## `unc-heretic`

| Setup | Gewichte (GB) | Schichten | Tempo leer | Tempo 17k | Prompt | MTP | Laden | Hinweis |
|---|---|---|---|---|---|---|---|---|
| standard | 5070Ti 8,1 / 3060 7,0 / CPU 0,7 | 66/66 | 49.9 Tok./s | 49.7 Tok./s | 833 Tok./s | ja | 6.2 s | Ollama/llama.cpp decide (layer split by free memory) |
| split-65-35 | 5070Ti 9,2 / 3060 6,0 / CPU 0,7 | 66/66 | 54.9 Tok./s | 52.8 Tok./s | 921.4 Tok./s | ja | 5.2 s | more layers on the 5070 Ti |
| split-75-25 | - | - | - | - | - | - | - | FEHLER: Der Remoteserver hat einen Fehler zurückgegeben: (500) Interner Serverfehler. |
| split-70-30 | 5070Ti 10,0 / 3060 5,1 / CPU 0,7 | 66/66 | 60.1 Tok./s | 58.2 Tok./s | 1047 Tok./s | ja | 5.2 s | more layers on the 5070 Ti |

## `unc-blackfrost`

| Setup | Gewichte (GB) | Schichten | Tempo leer | Tempo 17k | Prompt | MTP | Laden | Hinweis |
|---|---|---|---|---|---|---|---|---|
| standard | 5070Ti 8,1 / 3060 6,8 / CPU 0,7 | 66/66 | 47.5 Tok./s | 48.2 Tok./s | 833.8 Tok./s | ja | 5.8 s | Ollama/llama.cpp decide (layer split by free memory) |
| split-65-35 | 5070Ti 9,2 / 3060 5,8 / CPU 0,7 | 66/66 | 54.9 Tok./s | 55.6 Tok./s | 924.7 Tok./s | ja | 7.7 s | more layers on the 5070 Ti |
| split-75-25 | - | - | - | - | - | - | - | FEHLER: Der Remoteserver hat einen Fehler zurückgegeben: (500) Interner Serverfehler. |
| split-70-30 | 5070Ti 10,0 / 3060 4,9 / CPU 0,7 | 66/66 | 59.9 Tok./s | 54.4 Tok./s | 1044.3 Tok./s | ja | 5.1 s | more layers on the 5070 Ti |

## `unc-coletti`

| Setup | Gewichte (GB) | Schichten | Tempo leer | Tempo 17k | Prompt | MTP | Laden | Hinweis |
|---|---|---|---|---|---|---|---|---|
| standard | 5070Ti 8,1 / 3060 6,8 / CPU 0,7 | 66/66 | 49.3 Tok./s | 52 Tok./s | 830.2 Tok./s | ja | 6 s | Ollama/llama.cpp decide (layer split by free memory) |
| split-65-35 | 5070Ti 9,2 / 3060 5,8 / CPU 0,7 | 66/66 | 53.3 Tok./s | 55.8 Tok./s | 929.4 Tok./s | ja | 6.8 s | more layers on the 5070 Ti |
| split-75-25 | - | - | - | - | - | - | - | FEHLER: Der Remoteserver hat einen Fehler zurückgegeben: (500) Interner Serverfehler. |
| split-70-30 | 5070Ti 10,0 / 3060 4,9 / CPU 0,7 | 66/66 | 62 Tok./s | 55.7 Tok./s | 1048.8 Tok./s | ja | 5.2 s | more layers on the 5070 Ti |

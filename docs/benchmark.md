# Benchmark-Ergebnisse

Automatisch erzeugt von `scripts\Benchmark-Models.ps1`. Nicht von Hand bearbeiten.
Stand: 2026-11-17 15:51. Rohdaten: `logs\benchmark\results.jsonl`.
Zeilen mit Backend `Ollama` stammen aus der Zeit vor dem Umbau auf llama.cpp (bis 2026-11-14).

## Rohwerte

| Backend | Profil | Modell | Kontext | Lauf | GPU-Speicher | Laden | Antwort-Tempo | MTP-Treffer | Prompt-Tempo | Tool-Calls |
|---|---|---|---|---|---|---|---|---|---|---|
| llama.cpp | `gpt-oss-20b` | `gpt-oss-20b-MXFP4.gguf` | 64k | lean | RTX 5070 Ti 12238, RTX 3060 502 MiB | 4.6 s | 211.4 Tok./s | - | 9335.7 Tok./s | OK |
| llama.cpp | `gpt-oss-20b` | `gpt-oss-20b-MXFP4.gguf` | 64k | planner | RTX 5070 Ti 12238, RTX 3060 0 MiB | 4.1 s | 212.0 Tok./s | - | 9362.7 Tok./s | OK |
| llama.cpp | `local-coder` | `qwen3.6-27b-heretic-v2-Q4_K_M-mtp.gguf` | 64k | lean | RTX 5070 Ti 13580, RTX 3060 8048 MiB | 10.5 s | 37.0 Tok./s | 59 % | 1198.7 Tok./s | OK |
| llama.cpp | `local-coder` | `qwen3.6-27b-heretic-v2-Q4_K_M-mtp.gguf` | 64k | lean2 | RTX 5070 Ti 13580, RTX 3060 7529 MiB | 6.1 s | 60.4 Tok./s | 62 % | 1475.7 Tok./s | OK |
| llama.cpp | `local-coder` | `qwen3.6-27b-heretic-v2-Q4_K_M-mtp.gguf` | 64k | planner | RTX 5070 Ti 13580, RTX 3060 7529 MiB | 6.1 s | 62.7 Tok./s | 66 % | 1493.8 Tok./s | OK |
| llama.cpp | `local-coder` | `qwen3.6-27b-heretic-v2-Q4_K_M-mtp.gguf` | 64k | planner2 | RTX 5070 Ti 13580, RTX 3060 7529 MiB | 6.2 s | 62.7 Tok./s | 66 % | 1492.8 Tok./s | OK |
| llama.cpp | `local-coder` | `qwen3.6-27b-heretic-v2-Q4_K_M-mtp.gguf` | 64k | stufe2 | RTX 5070 Ti 14718, RTX 3060 7529 MiB | 9.3 s | 63.3 Tok./s | 68 % | 1320.8 Tok./s | OK |
| llama.cpp | `local-coder` | `qwen3.6-27b-heretic-v2-Q4_K_M-mtp.gguf` | 64k | stufe3 | RTX 5070 Ti 14718, RTX 3060 7529 MiB | 6.8 s | 59.8 Tok./s | 61 % | 1318.9 Tok./s | OK |
| llama.cpp | `local-coder` | `qwen3.6-27b-heretic-v2-Q4_K_M-mtp.gguf` | 64k | stufe3b | RTX 5070 Ti 14718, RTX 3060 7529 MiB | 8.9 s | 58.2 Tok./s | 59 % | 1315.8 Tok./s | OK |
| llama.cpp | `local-coder` | `qwen3.6-27b-heretic-v2-Q4_K_M-mtp.gguf` | 64k | stufe3-befehl | RTX 5070 Ti 14718, RTX 3060 7529 MiB | 6.7 s | 56.4 Tok./s | 56 % | 1316.2 Tok./s | OK |
| llama.cpp | `local-coder` | `qwen3.6-27b-heretic-v2-Q4_K_M-mtp.gguf` | 64k | stufe3-projekt | RTX 5070 Ti 14718, RTX 3060 7529 MiB | 7.7 s | 61.4 Tok./s | 63 % | 1314.2 Tok./s | OK |
| llama.cpp | `local-coder` | `qwen3.6-27b-heretic-v2-Q4_K_M-mtp.gguf` | 128k | b12433 | RTX 5070 Ti 15582, RTX 3060 10371 MiB | 7.2 s | 59.2 Tok./s | 63 % | 1312.1 Tok./s | OK |
| llama.cpp | `local-coder` | `qwen3.6-27b-heretic-v2-Q4_K_M-mtp.gguf` | 128k | h3-probe | RTX 5070 Ti 15588, RTX 3060 10371 MiB | 6.7 s | 61.8 Tok./s | 63 % | 1509.4 Tok./s | OK |
| llama.cpp | `local-coder` | `qwen3.6-27b-heretic-v2-Q4_K_M-mtp.gguf` | 128k | h4 | RTX 5070 Ti 15588, RTX 3060 10371 MiB | 7.2 s | 66.0 Tok./s | 69 % | 1503.8 Tok./s | OK |
| llama.cpp | `local-coder` | `qwen3.6-27b-heretic-v2-Q4_K_M-mtp.gguf` | 128k | stufe4 | RTX 5070 Ti 15582, RTX 3060 10371 MiB | 7.4 s | 61.0 Tok./s | 64 % | 1306.0 Tok./s | OK |
| llama.cpp | `local-coder` | `qwen3.6-27b-heretic-v2-Q4_K_M-mtp.gguf` | 128k | stufe4-128k | RTX 5070 Ti 15588, RTX 3060 10371 MiB | 7.2 s | 57.5 Tok./s | 57 % | 1314.2 Tok./s | OK |
| llama.cpp | `local-fast` | `qwen3.6-35b-a3b-heretic-Q4_K_M-mtp.gguf` | 64k | lean | RTX 5070 Ti 13996, RTX 3060 9813 MiB | 11.9 s | 83.4 Tok./s | 64 % | 2985.5 Tok./s | OK |
| llama.cpp | `local-fast` | `qwen3.6-35b-a3b-heretic-Q4_K_M-mtp.gguf` | 64k | planner | RTX 5070 Ti 13996, RTX 3060 9830 MiB | 11.4 s | 82.4 Tok./s | 61 % | 2990.4 Tok./s | OK |
| llama.cpp | `local-fast` | `qwen3.6-35b-a3b-heretic-Q4_K_M-mtp.gguf` | 64k | stufe2 | RTX 5070 Ti 15108, RTX 3060 9311 MiB | 17.1 s | 129.1 Tok./s | 60 % | 3497.3 Tok./s | OK |
| llama.cpp | `qwen3-coder-30b` | `qwen3-coder-30b-Q4_K_M.gguf` | 64k | llamacpp | RTX 5070 Ti 14318, RTX 3060 7761 MiB | 41.9 s | 144.6 Tok./s | - | 3834.8 Tok./s | OK |
| llama.cpp | `local-qwen38` | `unc-heretic-27b-Q4_K_M-mtp.gguf` | 64k | lean | RTX 5070 Ti 13286, RTX 3060 7613 MiB | 5.6 s | 55.4 Tok./s | 56 % | 1501.2 Tok./s | OK |
| llama.cpp | `local-qwen38` | `unc-heretic-27b-Q4_K_M-mtp.gguf` | 64k | llamacpp | RTX 5070 Ti 13286, RTX 3060 7613 MiB | 9.7 s | 58.1 Tok./s | 62 % | 1487.8 Tok./s | OK |
| llama.cpp | `local-qwen38` | `unc-heretic-27b-Q4_K_M-mtp.gguf` | 64k | planner | RTX 5070 Ti 13292, RTX 3060 7613 MiB | 5.7 s | 49.4 Tok./s | 48 % | 1487.6 Tok./s | OK |
| llama.cpp | `local-qwen38` | `unc-heretic-27b-Q4_K_M-mtp.gguf` | 64k | planner2 | RTX 5070 Ti 13292, RTX 3060 7613 MiB | 5.6 s | 53.7 Tok./s | 54 % | 1489.3 Tok./s | OK |
| Ollama | `deepseek-r1-32k` | `deepseek-r1:32b` | 32k | default | 23.1 GB, 100 % GPU | 56.4 s | 23.9 Tok./s | - | 740.5 Tok./s | FEHLER |
| Ollama | `deepseek-r1-64k` | `deepseek-r1:32b` | 64k | default | 28 GB, 83 % GPU | 6.7 s | 8.3 Tok./s | - | 529.8 Tok./s | FEHLER |
| Ollama | `devstral2-64k` | `devstral-small-2:24b` | 64k | default | 19.6 GB, 100 % GPU | 43.1 s | 28.7 Tok./s | - | 1315.8 Tok./s | OK |
| Ollama | `devstral2-96k` | `devstral-small-2:24b` | 96k | default | 22.7 GB, 91 % GPU | 34.2 s | 20.6 Tok./s | - | 981.9 Tok./s | OK |
| Ollama | `qwen38-unc-32k` | `mgraffam/qwen3.8-EfficientThink-uncensored:27b` | 32k | default | 19.6 GB, 100 % GPU | 41.5 s | 24.4 Tok./s | - | 1125.7 Tok./s | OK |
| Ollama | `qwen38-unc-64k` | `mgraffam/qwen3.8-EfficientThink-uncensored:27b` | 64k | default | 21.2 GB, 100 % GPU | 9.5 s | 24.6 Tok./s | - | 1447 Tok./s | OK |
| Ollama | `mimo-9b-64k` | `mimo-v2.6:9b-q8_0` | 64k | default | 11.2 GB, 100 % GPU | 23.9 s | 52.1 Tok./s | - | 3917.3 Tok./s | FEHLER |
| Ollama | `mimo-9b-128k` | `mimo-v2.6:9b-q8_0` | 128k | default | 12.5 GB, 100 % GPU | 4.1 s | 52.2 Tok./s | - | 3866.5 Tok./s | FEHLER |
| Ollama | `qwen38-32k` | `qwen3.8:27b` | 32k | default | 17.5 GB, 100 % GPU | 41.2 s | 14.6 Tok./s | - | 830.8 Tok./s | OK |
| Ollama | `qwen38-64k` | `qwen3.8:27b` | 64k | default | 18.7 GB, 100 % GPU | 10 s | 56.2 Tok./s | - | 876.7 Tok./s | OK |
| Ollama | `qwen3-8b-32k` | `qwen3:8b` | 32k | default | 7.2 GB, 100 % GPU | 13.8 s | 139.8 Tok./s | - | 5211.1 Tok./s | OK |
| Ollama | `qwen3-coder-32k` | `qwen3-coder:30b` | 32k | default | 19.7 GB, 100 % GPU | 46.6 s | 131.4 Tok./s | - | 3187.9 Tok./s | OK |
| Ollama | `qwen3-coder-64k` | `qwen3-coder:30b` | 64k | default | 21.2 GB, 100 % GPU | 5.1 s | 140.4 Tok./s | - | 2744 Tok./s | OK |
| Ollama | `unc-blackfrost-64k` | `unc-blackfrost:latest` | 64k | default | 18.3 GB, 100 % GPU | 8 s | 51.5 Tok./s | - | 795.1 Tok./s | OK |
| Ollama | `unc-blackfrost-64k` | `unc-blackfrost:latest` | 64k | repeat3 | 18.4 GB, 100 % GPU | 35.1 s | 60 Tok./s | - | 947.8 Tok./s | OK |
| Ollama | `unc-coletti-64k` | `unc-coletti:latest` | 64k | default | 18.3 GB, 100 % GPU | 8.4 s | 54.3 Tok./s | - | 790.6 Tok./s | OK |
| Ollama | `unc-coletti-64k` | `unc-coletti:latest` | 64k | repeat3 | 18.4 GB, 100 % GPU | 35.2 s | 62.5 Tok./s | - | 946.7 Tok./s | OK |
| Ollama | `unc-heretic-64k` | `unc-heretic:latest` | 64k | default | 18.5 GB, 100 % GPU | 8.7 s | 51.8 Tok./s | - | 791.2 Tok./s | OK |
| Ollama | `unc-heretic-64k` | `unc-heretic:latest` | 64k | repeat3 | 18.6 GB, 100 % GPU | 35 s | 58 Tok./s | - | 949.4 Tok./s | OK |

## Agenten-Aufgaben (ueber claude-local)

| Backend | Profil | Lauf | Bestanden | Summe Zeit | Regeln eingehalten |
|---|---|---|---|---|---|
| llama.cpp | `gpt-oss-20b` | lean | 9 / 9 | 166 s | - |
| llama.cpp | `gpt-oss-20b` | planner | 1 / 3 | 237 s | - |
| llama.cpp | `local-coder` | lean | 9 / 9 | 673 s | - |
| llama.cpp | `local-coder` | lean2 | 9 / 9 | 327 s | - |
| llama.cpp | `local-coder` | planner | 3 / 3 | 461 s | - |
| llama.cpp | `local-coder` | planner2 | 3 / 3 | 474 s | - |
| llama.cpp | `local-coder` | stufe2 | 9 / 15 | 3970 s | 43 / 66 (65 %) |
| llama.cpp | `local-coder` | stufe3 | 11 / 15 | 5494 s | 51 / 66 (77 %) |
| llama.cpp | `local-coder` | stufe3b | 12 / 15 | 5951 s | 56 / 66 (85 %) |
| llama.cpp | `local-coder` | stufe3-befehl | 2 / 3 | 914 s | 15 / 15 (100 %) |
| llama.cpp | `local-coder` | stufe3-projekt | 10 / 15 | 6555 s | 60 / 66 (91 %) |
| llama.cpp | `local-coder` | b12433 | 13 / 15 | 4463 s | 60 / 66 (91 %) |
| llama.cpp | `local-coder` | h3-probe | 1 / 1 | 205 s | 5 / 5 (100 %) |
| llama.cpp | `local-coder` | h4 | 6 / 6 | 786 s | 27 / 30 (90 %) |
| llama.cpp | `local-coder` | stufe4 | 14 / 15 | 4903 s | 59 / 66 (89 %) |
| llama.cpp | `local-coder` | stufe4-128k | 1 / 3 | 42290 s | 12 / 12 (100 %) |
| llama.cpp | `local-fast` | lean | 9 / 9 | 266 s | - |
| llama.cpp | `local-fast` | planner | 1 / 3 | 846 s | - |
| llama.cpp | `local-fast` | stufe2 | 3 / 15 | 3679 s | 34 / 66 (52 %) |
| llama.cpp | `qwen3-coder-30b` | llamacpp | 7 / 9 | 1709 s | - |
| llama.cpp | `local-qwen38` | lean | 9 / 9 | 375 s | - |
| llama.cpp | `local-qwen38` | llamacpp | 9 / 9 | 431 s | - |
| llama.cpp | `local-qwen38` | planner | 3 / 3 | 904 s | - |
| llama.cpp | `local-qwen38` | planner2 | 2 / 3 | 1521 s | - |
| Ollama | `deepseek-r1-32k` | default | 0 / 3 | 120 s | - |
| Ollama | `deepseek-r1-64k` | default | 0 / 3 | 497 s | - |
| Ollama | `devstral2-64k` | default | 1 / 3 | 273 s | - |
| Ollama | `devstral2-96k` | default | 1 / 3 | 301 s | - |
| Ollama | `qwen38-unc-32k` | default | 0 / 3 | 1260 s | - |
| Ollama | `qwen38-unc-64k` | default | 3 / 3 | 536 s | - |
| Ollama | `mimo-9b-64k` | default | 2 / 3 | 362 s | - |
| Ollama | `mimo-9b-128k` | default | 2 / 3 | 463 s | - |
| Ollama | `qwen38-32k` | default | 3 / 3 | 1012 s | - |
| Ollama | `qwen38-64k` | default | 3 / 3 | 252 s | - |
| Ollama | `qwen3-8b-32k` | default | 0 / 3 | 357 s | - |
| Ollama | `qwen3-coder-32k` | default | 0 / 3 | 151 s | - |
| Ollama | `qwen3-coder-64k` | default | 3 / 3 | 172 s | - |
| Ollama | `unc-blackfrost-64k` | default | 3 / 3 | 289 s | - |
| Ollama | `unc-blackfrost-64k` | repeat3 | 9 / 9 | 1675 s | - |
| Ollama | `unc-coletti-64k` | default | 3 / 3 | 326 s | - |
| Ollama | `unc-coletti-64k` | repeat3 | 9 / 9 | 1015 s | - |
| Ollama | `unc-heretic-64k` | default | 3 / 3 | 653 s | - |
| Ollama | `unc-heretic-64k` | repeat3 | 9 / 9 | 993 s | - |

### Je Aufgabe

| Backend | Profil | Lauf | Aufgabe | Bestanden | Laeufe | Regeln eingehalten |
|---|---|---|---|---|---|---|
| llama.cpp | `gpt-oss-20b` | lean | bugfix | 3 / 3 | ja (6 s), ja (27 s), ja (8 s) | - |
| llama.cpp | `gpt-oss-20b` | lean | feature | 3 / 3 | ja (14 s), ja (14 s), ja (13 s) | - |
| llama.cpp | `gpt-oss-20b` | lean | multifile | 3 / 3 | ja (37 s), ja (18 s), ja (29 s) | - |
| llama.cpp | `gpt-oss-20b` | planner | planner | 1 / 3 | nein (25 s), ja (210 s), nein (2 s) | - |
| llama.cpp | `local-coder` | lean | bugfix | 3 / 3 | ja (33 s), ja (31 s), ja (30 s) | - |
| llama.cpp | `local-coder` | lean | feature | 3 / 3 | ja (83 s), ja (119 s), ja (84 s) | - |
| llama.cpp | `local-coder` | lean | multifile | 3 / 3 | ja (86 s), ja (136 s), ja (71 s) | - |
| llama.cpp | `local-coder` | lean2 | bugfix | 3 / 3 | ja (25 s), ja (23 s), ja (24 s) | - |
| llama.cpp | `local-coder` | lean2 | feature | 3 / 3 | ja (59 s), ja (33 s), ja (34 s) | - |
| llama.cpp | `local-coder` | lean2 | multifile | 3 / 3 | ja (39 s), ja (39 s), ja (51 s) | - |
| llama.cpp | `local-coder` | planner | planner | 3 / 3 | ja (137 s), ja (135 s), ja (189 s) | - |
| llama.cpp | `local-coder` | planner2 | planner | 3 / 3 | ja (149 s), ja (139 s), ja (186 s) | - |
| llama.cpp | `local-coder` | stufe2 | extend | 3 / 3 | ja (251 s), ja (191 s), ja (171 s) | 7 / 15 (47 %) |
| llama.cpp | `local-coder` | stufe2 | refactor | 3 / 3 | ja (319 s), ja (216 s), ja (187 s) | 8 / 12 (67 %) |
| llama.cpp | `local-coder` | stufe2 | psscript | 0 / 3 | nein (465 s), nein (431 s), nein (356 s) | 10 / 15 (67 %) |
| llama.cpp | `local-coder` | stufe2 | screenshot | 3 / 3 | ja (88 s), ja (75 s), ja (67 s) | 10 / 12 (83 %) |
| llama.cpp | `local-coder` | stufe2 | longcontext | 0 / 3 | nein (278 s), nein (557 s), nein (318 s) | 8 / 12 (67 %) |
| llama.cpp | `local-coder` | stufe3 | extend | 2 / 3 | ja (203 s), nein (222 s), ja (210 s) | 9 / 15 (60 %) |
| llama.cpp | `local-coder` | stufe3 | refactor | 3 / 3 | ja (387 s), ja (259 s), ja (241 s) | 9 / 12 (75 %) |
| llama.cpp | `local-coder` | stufe3 | psscript | 3 / 3 | ja (496 s), ja (468 s), ja (566 s) | 12 / 15 (80 %) |
| llama.cpp | `local-coder` | stufe3 | screenshot | 3 / 3 | ja (109 s), ja (73 s), ja (308 s) | 12 / 12 (100 %) |
| llama.cpp | `local-coder` | stufe3 | longcontext | 0 / 3 | nein (606 s), nein (656 s), nein (690 s) | 9 / 12 (75 %) |
| llama.cpp | `local-coder` | stufe3b | extend | 3 / 3 | ja (348 s), ja (377 s), ja (402 s) | 12 / 15 (80 %) |
| llama.cpp | `local-coder` | stufe3b | refactor | 3 / 3 | ja (400 s), ja (290 s), ja (503 s) | 12 / 12 (100 %) |
| llama.cpp | `local-coder` | stufe3b | psscript | 3 / 3 | ja (572 s), ja (553 s), ja (507 s) | 12 / 15 (80 %) |
| llama.cpp | `local-coder` | stufe3b | screenshot | 3 / 3 | ja (128 s), ja (102 s), ja (135 s) | 12 / 12 (100 %) |
| llama.cpp | `local-coder` | stufe3b | longcontext | 0 / 3 | nein (554 s), nein (363 s), nein (717 s) | 8 / 12 (67 %) |
| llama.cpp | `local-coder` | stufe3-befehl | extend | 2 / 3 | nein (320 s), ja (335 s), ja (259 s) | 15 / 15 (100 %) |
| llama.cpp | `local-coder` | stufe3-projekt | extend | 3 / 3 | ja (266 s), ja (317 s), ja (346 s) | 15 / 15 (100 %) |
| llama.cpp | `local-coder` | stufe3-projekt | refactor | 3 / 3 | ja (394 s), ja (368 s), ja (204 s) | 12 / 12 (100 %) |
| llama.cpp | `local-coder` | stufe3-projekt | psscript | 2 / 3 | Zeit, Dateien ok (900 s), ja (883 s), ja (842 s) | 13 / 15 (87 %) |
| llama.cpp | `local-coder` | stufe3-projekt | screenshot | 2 / 3 | nein (67 s), ja (61 s), ja (64 s) | 12 / 12 (100 %) |
| llama.cpp | `local-coder` | stufe3-projekt | longcontext | 0 / 3 | nein (556 s), nein (804 s), nein (483 s) | 8 / 12 (67 %) |
| llama.cpp | `local-coder` | b12433 | extend | 3 / 3 | ja (297 s), ja (285 s), ja (304 s) | 13 / 15 (87 %) |
| llama.cpp | `local-coder` | b12433 | refactor | 3 / 3 | ja (286 s), ja (224 s), ja (289 s) | 11 / 12 (92 %) |
| llama.cpp | `local-coder` | b12433 | psscript | 3 / 3 | ja (654 s), ja (309 s), ja (258 s) | 12 / 15 (80 %) |
| llama.cpp | `local-coder` | b12433 | screenshot | 3 / 3 | ja (110 s), ja (101 s), ja (103 s) | 12 / 12 (100 %) |
| llama.cpp | `local-coder` | b12433 | longcontext | 1 / 3 | ja (374 s), nein (409 s), nein (460 s) | 12 / 12 (100 %) |
| llama.cpp | `local-coder` | h3-probe | datenblatt | 1 / 1 | ja (205 s) | 5 / 5 (100 %) |
| llama.cpp | `local-coder` | h4 | datenblatt | 3 / 3 | ja (129 s), ja (198 s), ja (121 s) | 12 / 15 (80 %) |
| llama.cpp | `local-coder` | h4 | pinwechsel | 3 / 3 | ja (103 s), ja (105 s), ja (130 s) | 15 / 15 (100 %) |
| llama.cpp | `local-coder` | stufe4 | extend | 3 / 3 | ja (334 s), ja (245 s), ja (241 s) | 12 / 15 (80 %) |
| llama.cpp | `local-coder` | stufe4 | refactor | 3 / 3 | ja (264 s), ja (248 s), ja (244 s) | 12 / 12 (100 %) |
| llama.cpp | `local-coder` | stufe4 | psscript | 3 / 3 | ja (446 s), ja (636 s), ja (566 s) | 12 / 15 (80 %) |
| llama.cpp | `local-coder` | stufe4 | screenshot | 3 / 3 | ja (113 s), ja (138 s), ja (146 s) | 12 / 12 (100 %) |
| llama.cpp | `local-coder` | stufe4 | longcontext | 2 / 3 | ja (494 s), ja (382 s), nein (406 s) | 11 / 12 (92 %) |
| llama.cpp | `local-coder` | stufe4-128k | longcontext | 1 / 3 | ja (429 s), nein (41474 s), nein (387 s) | 12 / 12 (100 %) |
| llama.cpp | `local-fast` | lean | bugfix | 3 / 3 | ja (21 s), ja (25 s), ja (25 s) | - |
| llama.cpp | `local-fast` | lean | feature | 3 / 3 | ja (32 s), ja (36 s), ja (27 s) | - |
| llama.cpp | `local-fast` | lean | multifile | 3 / 3 | ja (31 s), ja (34 s), ja (35 s) | - |
| llama.cpp | `local-fast` | planner | planner | 1 / 3 | nein (146 s), Zeit, Dateien ok (600 s), ja (100 s) | - |
| llama.cpp | `local-fast` | stufe2 | extend | 1 / 3 | nein (186 s), ja (189 s), nein (119 s) | 5 / 15 (33 %) |
| llama.cpp | `local-fast` | stufe2 | refactor | 2 / 3 | ja (120 s), Zeit (600 s), ja (98 s) | 9 / 12 (75 %) |
| llama.cpp | `local-fast` | stufe2 | psscript | 0 / 3 | nein (240 s), Zeit (900 s), nein (548 s) | 7 / 15 (47 %) |
| llama.cpp | `local-fast` | stufe2 | screenshot | 0 / 3 | nein (41 s), nein (31 s), nein (72 s) | 6 / 12 (50 %) |
| llama.cpp | `local-fast` | stufe2 | longcontext | 0 / 3 | nein (305 s), nein (108 s), nein (122 s) | 7 / 12 (58 %) |
| llama.cpp | `qwen3-coder-30b` | llamacpp | bugfix | 3 / 3 | ja (300 s), ja (214 s), ja (261 s) | - |
| llama.cpp | `qwen3-coder-30b` | llamacpp | feature | 2 / 3 | ja (60 s), ja (56 s), nein (177 s) | - |
| llama.cpp | `qwen3-coder-30b` | llamacpp | multifile | 2 / 3 | Zeit, Dateien ok (420 s), ja (103 s), ja (118 s) | - |
| llama.cpp | `local-qwen38` | lean | bugfix | 3 / 3 | ja (20 s), ja (27 s), ja (23 s) | - |
| llama.cpp | `local-qwen38` | lean | feature | 3 / 3 | ja (65 s), ja (39 s), ja (52 s) | - |
| llama.cpp | `local-qwen38` | lean | multifile | 3 / 3 | ja (45 s), ja (54 s), ja (50 s) | - |
| llama.cpp | `local-qwen38` | llamacpp | bugfix | 3 / 3 | ja (32 s), ja (29 s), ja (29 s) | - |
| llama.cpp | `local-qwen38` | llamacpp | feature | 3 / 3 | ja (68 s), ja (65 s), ja (42 s) | - |
| llama.cpp | `local-qwen38` | llamacpp | multifile | 3 / 3 | ja (88 s), ja (42 s), ja (36 s) | - |
| llama.cpp | `local-qwen38` | planner | planner | 3 / 3 | ja (216 s), ja (353 s), ja (335 s) | - |
| llama.cpp | `local-qwen38` | planner2 | planner | 2 / 3 | ja (356 s), Zeit, Dateien ok (600 s), ja (565 s) | - |
| Ollama | `deepseek-r1-32k` | default | bugfix | 0 / 1 | nein (52 s) | - |
| Ollama | `deepseek-r1-32k` | default | feature | 0 / 1 | nein (24 s) | - |
| Ollama | `deepseek-r1-32k` | default | multifile | 0 / 1 | nein (44 s) | - |
| Ollama | `deepseek-r1-64k` | default | bugfix | 0 / 1 | nein (135 s) | - |
| Ollama | `deepseek-r1-64k` | default | feature | 0 / 1 | nein (215 s) | - |
| Ollama | `deepseek-r1-64k` | default | multifile | 0 / 1 | nein (147 s) | - |
| Ollama | `devstral2-64k` | default | bugfix | 0 / 1 | nein (12 s) | - |
| Ollama | `devstral2-64k` | default | feature | 1 / 1 | ja (79 s) | - |
| Ollama | `devstral2-64k` | default | multifile | 0 / 1 | nein (182 s) | - |
| Ollama | `devstral2-96k` | default | bugfix | 0 / 1 | nein (15 s) | - |
| Ollama | `devstral2-96k` | default | feature | 1 / 1 | ja (93 s) | - |
| Ollama | `devstral2-96k` | default | multifile | 0 / 1 | nein (193 s) | - |
| Ollama | `qwen38-unc-32k` | default | bugfix | 0 / 1 | Zeit, Dateien ok (420 s) | - |
| Ollama | `qwen38-unc-32k` | default | feature | 0 / 1 | Zeit, Dateien ok (420 s) | - |
| Ollama | `qwen38-unc-32k` | default | multifile | 0 / 1 | Zeit, Dateien ok (420 s) | - |
| Ollama | `qwen38-unc-64k` | default | bugfix | 1 / 1 | ja (79 s) | - |
| Ollama | `qwen38-unc-64k` | default | feature | 1 / 1 | ja (272 s) | - |
| Ollama | `qwen38-unc-64k` | default | multifile | 1 / 1 | ja (185 s) | - |
| Ollama | `mimo-9b-64k` | default | bugfix | 1 / 1 | ja (54 s) | - |
| Ollama | `mimo-9b-64k` | default | feature | 1 / 1 | ja (256 s) | - |
| Ollama | `mimo-9b-64k` | default | multifile | 0 / 1 | nein (52 s) | - |
| Ollama | `mimo-9b-128k` | default | bugfix | 1 / 1 | ja (91 s) | - |
| Ollama | `mimo-9b-128k` | default | feature | 0 / 1 | nein (318 s) | - |
| Ollama | `mimo-9b-128k` | default | multifile | 1 / 1 | ja (54 s) | - |
| Ollama | `qwen38-32k` | default | bugfix | 1 / 1 | ja (282 s) | - |
| Ollama | `qwen38-32k` | default | feature | 1 / 1 | ja (376 s) | - |
| Ollama | `qwen38-32k` | default | multifile | 1 / 1 | ja (354 s) | - |
| Ollama | `qwen38-64k` | default | bugfix | 1 / 1 | ja (41 s) | - |
| Ollama | `qwen38-64k` | default | feature | 1 / 1 | ja (142 s) | - |
| Ollama | `qwen38-64k` | default | multifile | 1 / 1 | ja (69 s) | - |
| Ollama | `qwen3-8b-32k` | default | bugfix | 0 / 1 | nein (93 s) | - |
| Ollama | `qwen3-8b-32k` | default | feature | 0 / 1 | nein (185 s) | - |
| Ollama | `qwen3-8b-32k` | default | multifile | 0 / 1 | nein (79 s) | - |
| Ollama | `qwen3-coder-32k` | default | bugfix | 0 / 1 | nein (23 s) | - |
| Ollama | `qwen3-coder-32k` | default | feature | 0 / 1 | nein (63 s) | - |
| Ollama | `qwen3-coder-32k` | default | multifile | 0 / 1 | nein (65 s) | - |
| Ollama | `qwen3-coder-64k` | default | bugfix | 1 / 1 | ja (48 s) | - |
| Ollama | `qwen3-coder-64k` | default | feature | 1 / 1 | ja (51 s) | - |
| Ollama | `qwen3-coder-64k` | default | multifile | 1 / 1 | ja (73 s) | - |
| Ollama | `unc-blackfrost-64k` | default | bugfix | 1 / 1 | ja (100 s) | - |
| Ollama | `unc-blackfrost-64k` | default | feature | 1 / 1 | ja (100 s) | - |
| Ollama | `unc-blackfrost-64k` | default | multifile | 1 / 1 | ja (89 s) | - |
| Ollama | `unc-blackfrost-64k` | repeat3 | bugfix | 3 / 3 | ja (168 s), ja (65 s), ja (77 s) | - |
| Ollama | `unc-blackfrost-64k` | repeat3 | feature | 3 / 3 | ja (412 s), ja (316 s), ja (122 s) | - |
| Ollama | `unc-blackfrost-64k` | repeat3 | multifile | 3 / 3 | ja (126 s), ja (257 s), ja (132 s) | - |
| Ollama | `unc-coletti-64k` | default | bugfix | 1 / 1 | ja (66 s) | - |
| Ollama | `unc-coletti-64k` | default | feature | 1 / 1 | ja (162 s) | - |
| Ollama | `unc-coletti-64k` | default | multifile | 1 / 1 | ja (98 s) | - |
| Ollama | `unc-coletti-64k` | repeat3 | bugfix | 3 / 3 | ja (65 s), ja (71 s), ja (110 s) | - |
| Ollama | `unc-coletti-64k` | repeat3 | feature | 3 / 3 | ja (181 s), ja (117 s), ja (155 s) | - |
| Ollama | `unc-coletti-64k` | repeat3 | multifile | 3 / 3 | ja (117 s), ja (75 s), ja (124 s) | - |
| Ollama | `unc-heretic-64k` | default | bugfix | 1 / 1 | ja (135 s) | - |
| Ollama | `unc-heretic-64k` | default | feature | 1 / 1 | ja (357 s) | - |
| Ollama | `unc-heretic-64k` | default | multifile | 1 / 1 | ja (161 s) | - |
| Ollama | `unc-heretic-64k` | repeat3 | bugfix | 3 / 3 | ja (70 s), ja (59 s), ja (68 s) | - |
| Ollama | `unc-heretic-64k` | repeat3 | feature | 3 / 3 | ja (156 s), ja (135 s), ja (146 s) | - |
| Ollama | `unc-heretic-64k` | repeat3 | multifile | 3 / 3 | ja (124 s), ja (140 s), ja (95 s) | - |

Legende: `ja` = Pruefung bestanden, `nein` = Ergebnis falsch, `Zeit` = Zeitlimit ueberschritten.
`Zeit, Dateien ok` = Zeitlimit ueberschritten, die Pruefung der Dateien waere aber bestanden; zaehlt als nicht bestanden.

### Arbeitsregeln

Wie oft der Agent eine Arbeitsregel aus `config\entwicklungsregeln.md` eingehalten hat, die der Auftrag nicht nennt.
Gezaehlt ueber alle Laeufe der Aufgaben, die die Regel pruefen (auch ueber nicht bestandene). `-` = nicht geprueft.

| Backend | Profil | Lauf | readme | tests | config | docstrings | headers | nodeadcode | fakten |
|---|---|---|---|---|---|---|---|---|---|
| llama.cpp | `local-coder` | stufe2 | 7 / 15 | 6 / 15 | 0 / 6 | 12 / 12 | 3 / 3 | 15 / 15 | - |
| llama.cpp | `local-coder` | stufe3 | 14 / 15 | 7 / 15 | 0 / 6 | 12 / 12 | 3 / 3 | 15 / 15 | - |
| llama.cpp | `local-coder` | stufe3b | 13 / 15 | 13 / 15 | 0 / 6 | 12 / 12 | 3 / 3 | 15 / 15 | - |
| llama.cpp | `local-coder` | stufe3-befehl | 3 / 3 | 3 / 3 | 3 / 3 | 3 / 3 | - | 3 / 3 | - |
| llama.cpp | `local-coder` | stufe3-projekt | 12 / 15 | 13 / 15 | 5 / 6 | 12 / 12 | 3 / 3 | 15 / 15 | - |
| llama.cpp | `local-coder` | b12433 | 15 / 15 | 14 / 15 | 1 / 6 | 12 / 12 | 3 / 3 | 15 / 15 | - |
| llama.cpp | `local-coder` | h3-probe | 1 / 1 | 1 / 1 | - | 1 / 1 | - | 1 / 1 | 1 / 1 |
| llama.cpp | `local-coder` | h4 | 6 / 6 | 6 / 6 | - | 6 / 6 | - | 3 / 6 | 6 / 6 |
| llama.cpp | `local-coder` | stufe4 | 15 / 15 | 15 / 15 | 0 / 6 | 11 / 12 | 3 / 3 | 15 / 15 | - |
| llama.cpp | `local-coder` | stufe4-128k | 3 / 3 | 3 / 3 | - | 3 / 3 | - | 3 / 3 | - |
| llama.cpp | `local-fast` | stufe2 | 4 / 15 | 2 / 15 | 0 / 6 | 11 / 12 | 2 / 3 | 15 / 15 | - |

`readme` = README angepasst, `tests` = Test fuer das Neue geschrieben, `config` = neue Einstellung in der Konfigurationsdatei statt im Code,
`docstrings` = neue oeffentliche Funktionen beschrieben, `headers` = neue Skripte mit Kopfkommentar, `nodeadcode` = kein auskommentierter Code,
`fakten` = neuer Fakt mit Quelle in facts/facts.json.
Die Bewertung dieser Zahlen steht in [modellwahl.md](modellwahl.md).

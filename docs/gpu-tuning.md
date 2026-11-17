# GPU-Aufteilung

> **Stand 2026-11-14:** Die Messungen in diesem Dokument stammen vom 2026-11-13 und liefen
> über Ollama. Die Erkenntnisse über die Hardware gelten weiter. Geändert hat sich die
> Einstellung: Seit dem Umbau auf llama.cpp hat jedes Modell seine eigene Aufteilung
> (`tensor-split` in `config\models.json`). `local-coder` läuft mit 70:30, `local-fast` mit
> 65:35; die Einschränkung aus dem Abschnitt „Warum 65:35 und nicht 70:30“ besteht nicht mehr.
> Die dort genannten Dateien und Skripte (`config\ollama.env.json`, `Set-OllamaEnv.ps1`,
> `Measure-GpuSetups.ps1`) gibt es nur noch in der Git-Historie.

Bewertung der Messwerte aus [gpu-setups.md](gpu-setups.md), gemessen am 2026-11-13 mit
`scripts\Measure-GpuSetups.ps1`. Hardware: RTX 5070 Ti (16 GB, PCIe 5.0 x16) und RTX 3060
(12 GB, **PCIe 4.0 x4**).

## Ergebnis in Kürze

- **PCIe x4 bremst nicht**, solange das Modell nach Schichten aufgeteilt wird (Standard von
  Ollama). Pro Token wandert nur ein Zwischenwert von wenigen KB über den Bus.
- **Der Engpass ist die 3060 selbst:** Speicher und Rechenleistung sind deutlich schwächer.
  Jede Schicht auf der 3060 kostet mehr Zeit als auf der 5070 Ti.
- **Deshalb so viel wie möglich auf die 5070 Ti legen.** Eingestellt ist
  `LLAMA_ARG_TENSOR_SPLIT=65,35` in `config\ollama.env.json`.
- **Der größte Hebel ist aber nicht die Aufteilung, sondern MTP** (spekulatives Dekodieren):
  Es verdoppelt das Tempo der Qwen-3.8-Modelle. Siehe [modellwahl.md](modellwahl.md).

## Beleg: PCIe x4 kostet nichts

Ein kleines Modell (`qwen3:8b`), das auf jede Karte allein passt:

| Setup | Antwort-Tempo | Prompt lesen |
|---|---|---|
| nur 5070 Ti | 144 Tok./s | 5926 Tok./s |
| nur 3060 | 54 Tok./s | 1285 Tok./s |
| auf beide verteilt (2,5 / 2,1 GB) | **86 Tok./s** | **3388 Tok./s** |

Würde der Bus bremsen, läge das verteilte Ergebnis unter dem, was sich aus den beiden
Einzelwerten ergibt. Rechnet man die Zeit pro Token aus den Anteilen der beiden Karten
zusammen, kommt man auf etwa 80 Tok./s beim Antworten und etwa 2200 Tok./s beim
Prompt-Lesen. Gemessen wurde mehr, weil beim Prompt beide Karten teilweise gleichzeitig
arbeiten.

## Beleg: die 3060 bremst

Die 3060 ist beim Antworten 2,6-mal und beim Prompt-Lesen 4,6-mal langsamer als die 5070 Ti.
Jede Schicht, die auf die 5070 Ti wandert, macht das Modell schneller:

| Modell | Standard | 65:35 | 70:30 | 75:25 |
|---|---|---|---|---|
| `unc-blackfrost` (bis 14.11. `local-coder`, entfernt) | 47,5 Tok./s | 54,9 | 59,9 | passt nicht |
| `unc-heretic` (seit 14.11. `local-coder`) | 49,9 Tok./s | 54,9 | 60,1 | passt nicht |
| `unc-coletti` (entfernt) | 49,3 Tok./s | 53,3 | 62,0 | passt nicht |
| `qwen3.8:27b` | 60,4 Tok./s | 60,1 | 63,4 | 66,7 ¹ |
| `local-fast` (`qwen3-coder:30b`) | 141 Tok./s | 137 | passt nicht | passt nicht |
| `local-legacy` (erstes `local-coder`, entfernt) | 25,1 Tok./s | 25,5 | passt nicht | 27,7 ¹ |

Beim Prompt-Lesen ist der Gewinn größer: bei `local-fast` 3242 → 3851 Tok./s (+19 %) mit
65:35, bei den MTP-Modellen etwa 830 → 925 (65:35) bzw. 1045 Tok./s (70:30).

¹ Läuft nur, weil Ollama nach dem ersten Fehlschlag den Bild-Encoder in den Arbeitsspeicher
verschiebt. Nicht verlässlich.

## Warum 65:35 und nicht 70:30

Die Aufteilung gilt für alle Modelle gleichzeitig: Ollama gibt die Variable an jeden
llama-server weiter, den es startet. `local-fast` passt bei 70:30 nicht mehr auf die 5070 Ti
und würde mit einem Fehler abbrechen, auch im Chat von Continue. 65:35 ist die größte
Aufteilung, mit der alle Modelle laden. Die MTP-Modelle verschenken damit gegenüber 70:30
etwa 9 % Tempo.

Wer `local-fast` nicht braucht, kann `LLAMA_ARG_TENSOR_SPLIT` auf `70,30` setzen
(`config\ollama.env.json`, dann `Set-OllamaEnv.ps1` und `Restart-Ollama.ps1`).

Das Autocomplete-Modell ist nicht betroffen: Ollama legt es mit `--split-mode none` auf eine
einzige Karte (die 3060). Geprüft: Beide Modelle passen auch mit 65:35 gleichzeitig ganz auf
die GPUs, in beiden Ladereihenfolgen.

## Was nicht hilft

| Setup | Ergebnis |
|---|---|
| `row` (jede Schicht auf beide Karten) | Startet in dieser Ollama-Version mit keinem Modell. |
| `tensor` (beide Karten rechnen an jeder Schicht) | Hier bremst PCIe x4 tatsächlich: Prompt-Lesen halbiert, `local-fast` antwortet 32 % langsamer. |
| `LLAMA_ARG_FIT_TARGET` (Reserve auf der 3060) | llama.cpp verschiebt dann Schichten in den Arbeitsspeicher statt auf die 5070 Ti. Bis zu dreimal langsamer. |
| `num_batch 1024` | Bei `local-fast` Prompt +16 %, Antworten −7 %. Bei den anderen Modellen kein Unterschied. |

## Fallstricke, die die Messung aufgedeckt hat

- **Modelle ohne Profil laden mit 262k Kontext.** Die Ollama-App gibt ihre Kontext-Einstellung
  (262144) an den Server weiter. Ein Modell ohne `num_ctx` im Profil belegt damit so viel Speicher,
  dass llama.cpp Schichten in den Arbeitsspeicher legt: `qwen3.8:27b` fiel so von 60 auf 14 Tok./s.
  Deshalb bekommt jedes benutzte Modell ein Profil in `modelfiles\`.
- **Ollama meldet „100 % GPU“, auch wenn Schichten im Arbeitsspeicher liegen.** Verlässlich ist
  die Zeile `offloaded X/Y layers` im Server-Log. Das Messskript wertet sie aus.
- **Ein Wechsel der Anfrage-Optionen lädt das Modell neu.** Schickt ein Programm ein anderes
  `num_ctx` als das Profil, lädt Ollama das Modell mit diesem Wert neu, ohne Meldung.

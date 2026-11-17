# Modelle und Profile

Ein **Profil** ist ein Eintrag in `config\models.json`: ein Name, eine GGUF-Datei und die
Optionen, mit denen `llama-server` sie lädt. Claude Code, Continue und die Skripte fragen
Modelle immer über den Profilnamen an.

## Vorhandene Profile

| Profil | Rolle | Modell | Download | Zweck |
|---|---|---|---|---|
| `local-coder` | agent | Qwen 3.6 27B, unzensiert (Heretic v2), Q4_K_M mit MTP | 17,2 GB | Standardmodell des Agenten ab 15 GB Grafikspeicher |
| `local-fast` | agent | Qwen 3.6 35B-A3B (Mixture of Experts), unzensiert (Heretic), Q4_K_M mit MTP | 22,7 GB | mehr Tokens pro Sekunde, bei schwereren Aufgaben weniger zuverlässig; Standardmodell unter 15 GB Grafikspeicher, weil es dort viel schneller ist (gemessen, [einrichtung.md](einrichtung.md)) |
| `local-qwen38` | agent | Qwen 3.8 27B, unzensiert (Heretic), Q4_K_M mit MTP | 17,6 GB | Standardmodell bis 2026-11-14, Prüfer des zweiten Blicks; braucht die eigene Chat-Vorlage |
| `qwen2.5-coder-1.5b-base` | autocomplete | Qwen 2.5 Coder 1.5B Basismodell | 1,6 GB | Tab-Vervollständigung in Continue |
| `local-coder-q5`, `-rb2048`, `-rb512`, `-rb0` | compare | Varianten von `local-coder` | | nur für den Benchmark |

Welches Modell ein Rechner bekommt, entscheidet der Installer nach dem Grafikspeicher
([einrichtung.md](einrichtung.md), Hardware-Stufen). Weitere lädt
`scripts\Get-Model.ps1 -Model <profil>`; `-List` zeigt, was installiert ist. Warum gerade
diese Modelle: [modellwahl.md](modellwahl.md).

## Aufbau von `config\models.json`

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
        "files": [ { "name": "<Datei im Modellordner>", "source": "<Datei im Repository>", "size": 17211797600, "sha256": "..." } ]
      },
      "args": { "mmproj": "qwen3.6-27b-mmproj-BF16.gguf", "ctx-size": 131072, ... }
    }
  }
}
```

- `role`: `agent` (für Claude Code, vom Installer angeboten), `autocomplete` (Continue)
  oder `compare` (nur Benchmark).
- `file` ist der Dateiname im Modellordner (`<installRoot>\models`).
- `download` sagt, woher `Get-Model.ps1` die Datei und den Bild-Encoder holt: Repository auf
  Hugging Face, fester Stand (Commit), je Datei Name im Repository, Größe und SHA-256.
  Ein Profilname statt des Objekts heißt: dieselben Dateien wie jenes Profil.
  `Test-Setup.ps1` prüft, dass der Eintrag alle Dateien des Profils nennt.
- `args` sind Optionen von `llama-server` ohne die führenden Striche. Die vollständige
  Liste zeigt `<installRoot>\<build>\llama-server.exe --help`.
- `defaults` gelten für jedes Profil; ein Wert in `args` überschreibt sie, `null` entfernt
  ihn.
- **Keine Aufteilung auf bestimmte Karten in dieser Datei.** llama.cpp verteilt das Modell
  selbst auf die vorhandenen Karten (`--fit`, voreingestellt) und legt, was nicht passt, in
  den Arbeitsspeicher. Werte für einen bestimmten Rechner (`tensor-split`, `device`,
  `mmproj-device`, `gpu-layers`, kleinerer Kontext) stehen in `config\machine.json` unter
  `models.<profil>.args` bzw. `modelDefaults` ([einrichtung.md](einrichtung.md)).
  `Test-Install.ps1` prüft das.

Nach jeder Änderung: `scripts\Restart-Server.ps1`, dann `scripts\Test-Model.ps1 -Model <name>`.

### Optionen, die hier benutzt werden

Die Werte von `gpu-layers`, `tensor-split`, `device` und `mmproj-device` gelten für den
Entwicklungsrechner (RTX 5070 Ti + RTX 3060) und stehen dort in `machine.json`.

| Option | Wert | Zweck |
|---|---|---|
| `gpu-layers` | `999` (Entwicklungsrechner) | Alle Schichten auf die Grafikkarten. Ohne Angabe entscheidet `--fit`. |
| `flash-attn` | `on` | Schnellere Attention, weniger Speicher |
| `cache-type-k`, `cache-type-v` | `q8_0` | Kontext-Cache in 8 Bit: etwa halber Speicherbedarf für den Kontext |
| `parallel` | `1` | Eine Anfrage zur Zeit. Jeder weitere Platz teilt das Kontextfenster. |
| `jinja` | `true` | Chat-Vorlage des Modells auswerten; nötig für Tool-Calls |
| `ctx-size` | `131072` | Kontextfenster in Tokens. Für Claude Code mindestens 64k; mit 128k bricht die lange Aufgabe nicht mehr ab ([modellwahl.md](modellwahl.md)). In einer Sitzung zählt das kleinste Fenster der Profile aus der Modellauswahl. |
| `tensor-split` | `70,30` (Entwicklungsrechner) | Anteil des Modells für RTX 5070 Ti und RTX 3060. Je mehr auf der schnelleren Karte liegt, desto schneller ([gpu-tuning.md](gpu-tuning.md)). `local-fast` ist größer und verträgt nur `60,40`. Ohne Angabe verteilt `--fit`. |
| `device` | `CUDA1` (Entwicklungsrechner) | Modell nur auf eine Karte legen (`CUDA0` = 5070 Ti, `CUDA1` = 3060; Liste: `llama-server.exe --list-devices`) |
| `spec-type` | `draft-mtp` | Spekulatives Dekodieren mit dem MTP-Kopf des Modells, siehe unten |
| `spec-draft-n-max` | `4` | Wie viele Tokens das Modell vorausrät |
| `chat-template-file` | `templates\qwen3.6-agent.jinja`, `templates\qwen3.8-agent.jinja` | Eigene Chat-Vorlage, Pfad relativ zu `config\`, siehe unten |
| `mmproj` | Dateiname in `modelsDir` | Bild-Encoder des Modells, siehe „Bilder“ |
| `mmproj-device` | `CUDA1` (Entwicklungsrechner) | Karte für den Bild-Encoder. Auf der RTX 3060 macht er 1,2 GB auf der RTX 5070 Ti frei, Bilder bleiben gleich schnell (gemessen). |
| `image-min-tokens` | `256` | Mindestzahl an Tokens je Bild; kleine Bilder werden dafür hochgerechnet, siehe „Bilder“ |
| `sleep-idle-seconds` | `1800` (in `defaults`) | Nach 30 Minuten ohne Anfrage gibt das Modell seinen GPU-Speicher frei und lädt bei der nächsten Anfrage neu ([backend.md](backend.md)) |
| `reasoning-effort` | `medium` | Denkaufwand, den die Chat-Vorlage dem Modell vorgibt |
| `temp`, `top-k`, `top-p`, `min-p`, `repeat-penalty` | je Modell | Sampling-Werte, die der Modellanbieter empfiehlt |

## MTP (Multi-Token Prediction)

Die Qwen-3.8-Modelle enthalten einen MTP-Kopf: Das Modell rät mehrere Tokens voraus und
prüft sie in einem Schritt. Mit `spec-type = draft-mtp` nutzt llama.cpp das als
spekulatives Dekodieren, was das Tempo etwa verdoppelt. Voraussetzung ist eine GGUF-Datei
**mit** MTP-Kopf (oft `-mtp` im Dateinamen, Angabe auf der Modellkarte).

Ob MTP läuft, zeigt `Test-Model.ps1` in der Zeile `speed` (`MTP on, 76 % of drafted tokens
accepted`). Modelle ohne MTP-Kopf bekommen die Option nicht.

## Bilder

Die drei Agenten-Modelle können Bilder lesen (Screenshots, Skizzen, Fotos von
Fehlermeldungen). Dafür braucht jedes Modell seinen Bild-Encoder, eine zweite GGUF-Datei
(`mmproj`), die im Profil unter `args` steht und neben dem Modell in `modelsDir` liegt.
Fehlt die Datei, lädt das Modell ohne Bild-Eingabe und `Start-Server.ps1` warnt.

In einer Sitzung gibt es zwei Wege: ein Bild in die Eingabe einfügen (Alt+V oder Datei ins
Terminal ziehen) oder den Pfad nennen, dann liest das Modell die Datei mit dem Werkzeug
`Read`.

`image-min-tokens = 256` rechnet kleine Bilder hoch. Gemessen mit `local-coder` am
2026-11-14: Von zwölf Bildern mit einer großen vierstelligen Zahl (448 × 224 Pixel) las das
Modell ohne die Option 5 richtig (etwa 100 Tokens je Bild), mit 256 und mit 1024 jeweils
alle 12. Acht Screenshots eines Terminals (1600 × 900, Schrift 11 pt, etwa 1400 Tokens je
Bild) las es in allen drei Einstellungen richtig. 256 kostet bei kleinen Bildern rund 300
Tokens Kontext, 1024 rund 1100. llama.cpp empfiehlt 1024 nur für Aufgaben, bei denen das
Modell Positionen im Bild angeben soll.

`Test-Model.ps1` prüft die Bild-Eingabe in der Zeile `image input`.

## Chat-Vorlage

Jede GGUF-Datei bringt eine Chat-Vorlage mit, die Nachrichten in das Textformat des Modells
übersetzt. Für die Arbeit mit Claude Code reichen die eingebauten Vorlagen nicht; alle drei
Agenten-Modelle nutzen deshalb eine Vorlage aus `config\templates\`. Jede ist die Vorlage
aus der GGUF-Datei mit den Änderungen, die im Kopf der Datei beschrieben sind.

| Vorlage | Profile | Änderungen |
|---|---|---|
| `qwen3.6-agent.jinja` | `local-coder`, `local-fast` | Reihenfolge der Tool-Ergebnisse |
| `qwen3.8-agent.jinja` | `local-qwen38` | Reihenfolge der Tool-Ergebnisse, spätere Systemnachrichten |

**Reihenfolge der Tool-Ergebnisse (Block „agent fix“).** Claude Code schickt das Ergebnis
eines Werkzeugs oft zusammen mit Text in einer Nachricht (Erinnerungen, Hinweise).
`llama-server` macht daraus „Text, dann Tool-Ergebnis“, also die falsche Reihenfolge
(`tools/server/server-chat.cpp`, auch im aktuellen Stand von llama.cpp). Die eingebaute
Vorlage von Qwen 3.6 bricht dann mit `A tool message must follow an assistant or tool
message.` ab, Claude Code zeigt Fehler 500 und versucht es mehrfach erneut. Die Vorlage
von Qwen 3.8 bricht nicht ab, zeigt dem Modell aber den Hinweis vor dem Ergebnis seines
eigenen Aufrufs. Der Block am Anfang der Vorlagen stellt die Tool-Ergebnisse direkt hinter
die Antwort, die sie angefordert hat. Aufgefallen ist der Fehler bei Bildern, er betraf
aber jedes Werkzeug.

**Spätere Systemnachrichten (nur Qwen 3.8).** Die eingebaute Vorlage bricht mit `System
message must be at the beginning.` ab, sobald eine Systemnachricht nicht an erster Stelle
steht. Claude Code schickt solche Nachrichten mitten im Gespräch. Die Vorlage gibt sie als
eigenen Systemblock aus.

Für ein neues Modell:

1. Modell laden und die eingebaute Vorlage auslesen:
   `curl http://127.0.0.1:8080/props?model=<profil>` (Feld `chat_template`).
2. Stimmt sie mit der eines vorhandenen Modells überein, dessen Vorlage eintragen. Sonst
   als `config\templates\<name>.jinja` speichern, den Block „agent fix“ aus einer
   vorhandenen Vorlage hinter die Prüfung `No messages provided` setzen und die Änderung
   im Kopf der Datei beschreiben.
3. Im Profil `"chat-template-file": "templates\\<name>.jinja"` eintragen.
4. `Test-Model.ps1` muss `image input: OK` zeigen; der Test schickt genau die Form, an der
   die eingebauten Vorlagen scheitern.

## Ein neues Modell aufnehmen

1. **Profil anlegen.** In `config\models.json` unter `models` einen Eintrag ergänzen;
   `local-coder` ist die Vorlage für Qwen-Modelle mit MTP. Mindestens `role`, `file`,
   `download` und `ctx-size`. Für `download` den Stand und die Prüfsummen von der API
   ablesen, nicht abschreiben:
   `curl.exe https://huggingface.co/api/models/<repo>` (Feld `sha`) und
   `.../api/models/<repo>/tree/main` (je Datei `size` und `lfs.oid` = SHA-256).
   Für Bilder die `mmproj`-Datei mit in `download.files` und in `args` eintragen.
   Chat-Vorlage prüfen, siehe oben.
2. **Laden:** `scripts\Get-Model.ps1 -Model <name>`. Eine Datei, die schon auf der Platte
   liegt, legt stattdessen `scripts\Add-Model.ps1 -Path D:\dl\modell.gguf -Name <file>`
   in den Modellordner (auf demselben Laufwerk als Hardlink ohne zusätzlichen Platz).
4. **Starten und prüfen:** `scripts\Restart-Server.ps1`, dann
   `scripts\Test-Model.ps1 -Model <name>`. Der Test muss `tool calling: OK` zeigen, sonst
   kann der Agent keine Dateien bearbeiten, und `image input: OK`, sonst scheitert er an
   Bildern und an Tool-Ergebnissen mit angehängtem Text.
5. **Mit dem Agenten ausprobieren:** `claude-local -Model <name>`.
6. **Vergleichen (optional):** Namen in `config\benchmark.json` unter `models` eintragen
   und `scripts\Benchmark-Models.ps1` starten.
7. **In die Auswahl aufnehmen (optional):** in `config\agent.json` unter `picker` und
   `aliases` eintragen ([agent.md](agent.md)).

Passt der GPU-Speicher nicht, hilft ein kleineres `ctx-size` oder ein anderes
`tensor-split`, beides für den eigenen Rechner in `config\machine.json`. Der Test zeigt den
belegten Speicher je Karte; frei bleiben sollten je Karte einige hundert MiB.

## Ein Modell entfernen

Eintrag aus `config\models.json` löschen (und aus `agent.json`, `benchmark.json`,
`setups.json`, `continue.config.yaml`, falls er dort steht), Server neu starten, dann die
Datei im Modellordner löschen. Nur auf einem Rechner entfernen: die Datei löschen; das
Profil fehlt dann in der Modellliste des Servers und in `/model`.

## Herkunft der Dateien

Die Quellen stehen im Feld `download` jedes Profils: Repository, fester Stand und SHA-256
je Datei, abgelesen von der Hugging-Face-API am 2026-11-17. Die Dateien auf dem
Entwicklungsrechner stimmen damit überein: Die Größen aller Modelldateien sind
byte-gleich, die SHA-256 der drei Bild-Encoder (`mmproj`) wurde am 2026-11-17 nachgerechnet
und stimmt. Damit ist auch ihre Quelle geklärt (vorher offener Punkt im
[Protokoll](protokoll.md)). Ausnahme: Die Autocomplete-Datei des Entwicklungsrechners
(Q4_K_M, aus Ollama) hat keine byte-gleiche Quelle; neue Rechner bekommen die Q8_0-Datei
von `ggml-org`, der Entwicklungsrechner behält seine über `machine.json`.

In `E:\LlamaCpp\models` (Entwicklungsrechner) liegt eine Datei ohne Profil: `gpt-oss-20b-MXFP4.gguf` (Hardlink auf
die Datei des Projekts Jarvis, belegt keinen zusätzlichen Platz). Die Datei von qwen3-coder
30B (früher `local-fast`) wurde am 2026-11-14 gelöscht. Warum beide ausgeschieden sind:
[modellwahl.md](modellwahl.md).

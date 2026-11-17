# Modelle und Profile

Ein **Profil** ist ein Eintrag in `config\models.json`: ein Name, eine GGUF-Datei und die
Optionen, mit denen `llama-server` sie lädt. Claude Code, Continue und die Skripte fragen
Modelle immer über den Profilnamen an.

## Vorhandene Profile

| Profil | Modell | Zweck |
|---|---|---|
| `local-coder` | Qwen 3.6 27B, unzensiert (Heretic v2), Q4_K_M mit MTP | Standardmodell des Agenten |
| `local-fast` | Qwen 3.6 35B-A3B (Mixture of Experts), unzensiert (Heretic), Q4_K_M mit MTP | mehr Tokens pro Sekunde, bei schwereren Aufgaben weniger zuverlässig |
| `local-qwen38` | Qwen 3.8 27B, unzensiert (Heretic), Q4_K_M mit MTP | Standardmodell bis 2026-11-14, zum Vergleich; braucht die eigene Chat-Vorlage |
| `qwen2.5-coder-1.5b-base` | Qwen 2.5 Coder 1.5B Basismodell | Tab-Vervollständigung in Continue |

Warum gerade diese Modelle: [modellwahl.md](modellwahl.md).

## Aufbau von `config\models.json`

```json
{
  "defaults": { "gpu-layers": 999, "flash-attn": "on", ... },
  "models": {
    "local-coder": {
      "description": "...",
      "file": "qwen3.6-27b-heretic-v2-Q4_K_M-mtp.gguf",
      "source": "woher die Datei stammt",
      "args": { "ctx-size": 131072, "tensor-split": "70,30", ... }
    }
  }
}
```

- `file` ist der Dateiname in `modelsDir` (`config\server.json`).
- `args` sind Optionen von `llama-server` ohne die führenden Striche. Die vollständige
  Liste zeigt `E:\LlamaCpp\<build>\llama-server.exe --help`.
- `defaults` gelten für jedes Profil; ein Wert in `args` überschreibt sie.
- `description` und `source` sind nur Dokumentation.

Nach jeder Änderung: `scripts\Restart-Server.ps1`, dann `scripts\Test-Model.ps1 -Model <name>`.

### Optionen, die hier benutzt werden

| Option | Wert | Zweck |
|---|---|---|
| `gpu-layers` | `999` | Alle Schichten auf die Grafikkarten |
| `flash-attn` | `on` | Schnellere Attention, weniger Speicher |
| `cache-type-k`, `cache-type-v` | `q8_0` | Kontext-Cache in 8 Bit: etwa halber Speicherbedarf für den Kontext |
| `parallel` | `1` | Eine Anfrage zur Zeit. Jeder weitere Platz teilt das Kontextfenster. |
| `jinja` | `true` | Chat-Vorlage des Modells auswerten; nötig für Tool-Calls |
| `ctx-size` | `131072` | Kontextfenster in Tokens. Für Claude Code mindestens 64k; mit 128k bricht die lange Aufgabe nicht mehr ab ([modellwahl.md](modellwahl.md)). In einer Sitzung zählt das kleinste Fenster der Profile aus der Modellauswahl. |
| `tensor-split` | `70,30` | Anteil des Modells für RTX 5070 Ti und RTX 3060. Je mehr auf der schnelleren Karte liegt, desto schneller ([gpu-tuning.md](gpu-tuning.md)). `local-fast` ist größer und verträgt nur `60,40`. |
| `device` | `CUDA1` | Modell nur auf eine Karte legen (`CUDA0` = 5070 Ti, `CUDA1` = 3060; Liste: `llama-server.exe --list-devices`) |
| `spec-type` | `draft-mtp` | Spekulatives Dekodieren mit dem MTP-Kopf des Modells, siehe unten |
| `spec-draft-n-max` | `4` | Wie viele Tokens das Modell vorausrät |
| `chat-template-file` | `templates\qwen3.6-agent.jinja`, `templates\qwen3.8-agent.jinja` | Eigene Chat-Vorlage, Pfad relativ zu `config\`, siehe unten |
| `mmproj` | Dateiname in `modelsDir` | Bild-Encoder des Modells, siehe „Bilder“ |
| `mmproj-device` | `CUDA1` | Karte für den Bild-Encoder. Auf der RTX 3060 macht er 1,2 GB auf der RTX 5070 Ti frei, Bilder bleiben gleich schnell (gemessen). |
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

1. **Datei beschaffen.** Von Hugging Face laden, zum Beispiel
   `curl.exe -L -C - -o D:\dl\modell.gguf https://huggingface.co/<repo>/resolve/main/<datei>.gguf`.
2. **In den Modellordner legen:**
   `scripts\Add-Model.ps1 -Path D:\dl\modell.gguf -Name <lesbarer-name>.gguf`.
   Liegt die Quelle auf demselben Laufwerk, entsteht ein Hardlink ohne zusätzlichen
   Speicherbedarf.
3. **Profil anlegen.** In `config\models.json` unter `models` einen Eintrag ergänzen;
   `local-coder` ist die Vorlage für Qwen-Modelle mit MTP. Mindestens `file` und `ctx-size`.
   Für Bilder die `mmproj`-Datei des Modells genauso in den Modellordner legen und im
   Profil eintragen. Chat-Vorlage prüfen, siehe oben.
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
`tensor-split`. Der Test zeigt den belegten Speicher je Karte; frei bleiben sollten je
Karte einige hundert MiB.

## Ein Modell entfernen

Eintrag aus `config\models.json` löschen (und aus `agent.json`, `benchmark.json`,
`continue.config.yaml`, falls er dort steht), Server neu starten, dann die Datei in
`modelsDir` löschen.

## Herkunft der Dateien

Die Quellen stehen im Feld `source` jedes Profils. Die beiden Qwen-3.6-Modelle wurden am
2026-11-14 von Hugging Face geladen und gegen die dort genannte SHA-256-Prüfsumme geprüft.
Die drei `mmproj`-Dateien kamen am selben Abend dazu; ihre Quelle ist nicht festgehalten
(offener Punkt im [Protokoll](protokoll.md)).

In `E:\LlamaCpp\models` liegt eine Datei ohne Profil: `gpt-oss-20b-MXFP4.gguf` (Hardlink auf
die Datei des Projekts Jarvis, belegt keinen zusätzlichen Platz). Die Datei von qwen3-coder
30B (früher `local-fast`) wurde am 2026-11-14 gelöscht. Warum beide ausgeschieden sind:
[modellwahl.md](modellwahl.md).

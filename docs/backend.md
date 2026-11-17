# Backend: llama.cpp

Der Server, der die Modelle auf die Grafikkarten lädt und Anfragen beantwortet, ist
`llama-server` aus [llama.cpp](https://github.com/ggml-org/llama.cpp).

## Bedienen

Aufruf jeweils mit `powershell -ExecutionPolicy Bypass -File scripts\<Name>`.

| Skript | Wirkung |
|---|---|
| `Start-Server.ps1` | Startet den Server, falls er nicht läuft, und zeigt die Modellprofile. |
| `Stop-Server.ps1` | Beendet den Server und alle geladenen Modelle. Gibt den GPU-Speicher frei. |
| `Restart-Server.ps1` | Beides nacheinander. Nötig nach jeder Änderung an `config\server.json` oder `config\models.json`. |
| `Test-Model.ps1 [-Model <name>]` | Lädt ein Profil und prüft Tempo, Tool-Calls, Bild-Eingabe und GPU-Speicher. |
| `Test-Setup.ps1` | Prüft Konfiguration und Skripte, ohne ein Modell zu laden. |

`claude-local` startet den Server selbst, wenn er nicht läuft. Für Continue muss er laufen;
nach einem Neustart des Rechners also einmal `Start-Server.ps1` oder `claude-local` ausführen.

Modelle werden bei der ersten Anfrage geladen (unzensiert etwa 8 s aus dem Datei-Cache, bis
zu 50 s von der Platte).

## Wann der GPU-Speicher frei wird

| Anlass | Wirkung | Einstellung |
|---|---|---|
| Die letzte Sitzung von `claude-local` endet | Die Modelle des Agenten werden entladen, der Server läuft weiter. Gemessen: 15,6 und 10,4 GB belegt (128k Kontext), danach 7 und 0 MiB. | `onExit` in `config\agent.json` ([agent.md](agent.md)) |
| 30 Minuten keine Anfrage an ein Modell | Das Modell schläft: Sein Prozess bleibt, gibt den Speicher aber frei (gemessen: 226 und 105 MiB Rest). Die nächste Anfrage weckt es in etwa 7 s; der Kontext-Cache ist dann leer, die Unterhaltung wird einmal neu eingelesen. | `sleep-idle-seconds` in `config\models.json` |
| Ein anderes Modell braucht den Platz | Der Server entlädt unbenutzte Modelle, bis das neue passt. | `memoryMarginMiB`, `modelsMax` |
| `Stop-Server.ps1` | Alles frei. | |

Der Server selbst belegt ohne geladenes Modell keinen GPU-Speicher. Die Leerlauf-Grenze
ist das Netz für die Fälle, in denen `claude-local` nicht aufräumen kann: Fenster
geschlossen, Absturz, oder das Modell wurde von Continue geladen. Abfragen des Zustands
(`/health`, `/models`, `/props`) zählen nicht als Anfrage.

## Einstellungen (`config\server.json`)

| Schlüssel | Wert | Zweck |
|---|---|---|
| `installRoot` | `E:\LlamaCpp` | Ordner für Programme, Protokoll und erzeugte Dateien |
| `build` | `b12433` | Version von llama.cpp (Tag der GitHub-Releases). Programme liegen in `<installRoot>\<build>\`. |
| `package` | `win-cuda-13.5-x64` | Variante des Downloads. Für ältere Treiber `win-cuda-12.4-x64`. |
| `modelsDir` | `E:\LlamaCpp\models` | Ordner der GGUF-Dateien |
| `host`, `port` | `127.0.0.1`, `8080` | Adresse des Servers. Nur vom eigenen Rechner erreichbar. |
| `requireApiKey` | `true` | Der Server verlangt bei jeder Anfrage einen Schlüssel. Er wird beim ersten Start erzeugt und liegt in `<installRoot>\run\api-key.txt` ([sicherheit.md](sicherheit.md)). |
| `corsOrigins` | `localhost` | Welche Webseiten Antworten des Servers im Browser lesen dürfen. Leer lassen für die Voreinstellung von llama.cpp (alle). |
| `modelsMax` | `3` | Höchstens so viele Modelle gleichzeitig geladen |
| `memoryMarginMiB` | `512` | Vor dem Laden eines Modells entlädt der Server so lange unbenutzte Modelle, bis das neue passt und je Karte so viel Speicher frei bleibt |
| `startTimeoutSeconds` | `60` | So lange warten die Skripte auf den Start des Servers |
| `loadTimeoutSeconds` | `300` | So lange warten Test und Benchmark auf das Laden eines Modells |

Steht die Adresse hier anders, muss sie auch in `config\continue.config.yaml` geändert werden.

## Wie der Server gestartet wird

`scripts\lib\Server.ps1` macht bei `Start-Server` drei Dinge:

1. Es erzeugt aus `config\models.json` die Datei `<installRoot>\run\models.ini`
   (das Format von `llama-server --models-preset`). Profile, deren GGUF-Datei fehlt,
   werden mit einer Warnung ausgelassen.
2. Es entfernt alle Variablen `LLAMA_ARG_*` aus der eigenen Umgebung. `llama-server` liest
   seine Optionen auch aus solchen Variablen; eine vergessene Variable (wie früher
   `LLAMA_ARG_TENSOR_SPLIT` aus der Ollama-Zeit) würde sonst unbemerkt jedes Modell
   beeinflussen.
3. Es startet `llama-server` im Router-Modus:
   `--models-preset <ini> --models-max <n> --models-memory-margin <MiB> --no-ui --offline
   --cors-origins <wert>`. Der Schlüssel geht über die Variable `LLAMA_API_KEY` an den
   Prozess, nicht über die Befehlszeile; so verlangen ihn auch die Modell-Prozesse.

Der Router startet für jedes angefragte Modell einen eigenen `llama-server`-Kindprozess mit
den Optionen des Profils. `Stop-Server` beendet nur Prozesse aus `installRoot`; ein
`llama-server` eines anderen Programms bleibt unberührt.

Der Server startet nicht mit Windows, siehe [einrichtung.md](einrichtung.md).

## Schnittstellen

| Schnittstelle | Adresse | Genutzt von |
|---|---|---|
| Anthropic-kompatibel | `http://127.0.0.1:8080/v1/messages` | Claude Code |
| OpenAI-kompatibel | `http://127.0.0.1:8080/v1/chat/completions` | Continue (Chat), Test- und Benchmark-Skripte |
| llama.cpp-eigen | `http://127.0.0.1:8080/completion` | Continue (Autocomplete) |
| Verwaltung | `GET /models`, `POST /models/load`, `POST /models/unload`, `GET /health` | Skripte |

Jede Anfrage nennt im Feld `model` den Namen eines Profils und schickt den Schlüssel des
Servers mit (`Authorization: Bearer <schlüssel>` oder `x-api-key`). Nur `/health` antwortet
ohne Schlüssel. Von Hand:

```
$key = Get-Content E:\LlamaCpp\run\api-key.txt
curl.exe -H "Authorization: Bearer $key" http://127.0.0.1:8080/models
```

## llama.cpp aktualisieren

1. Auf <https://github.com/ggml-org/llama.cpp/releases> einen neueren Build wählen.
2. In `config\server.json` den Wert `build` ändern.
3. `scripts\Install-LlamaCpp.ps1` ausführen. Lädt die Archive, prüft ihre SHA-256-Summen
   gegen die von GitHub veröffentlichten und entpackt nach `<installRoot>\<build>\`.
4. `scripts\Restart-Server.ps1`, dann `scripts\Test-Model.ps1`.
5. Bei Zweifeln `scripts\Benchmark-Models.ps1 -Label <build>` und mit dem vorigen Lauf
   vergleichen. Zurück geht es, indem `build` wieder auf den alten Wert gesetzt wird; der
   alte Ordner bleibt liegen, bis man ihn löscht.

## Fehlersuche

Das Protokoll des Servers und aller Modellprozesse ist `E:\LlamaCpp\logs\server.log`.

| Symptom | Ursache und Abhilfe |
|---|---|
| `llama-server not found` | `scripts\Install-LlamaCpp.ps1` ausführen. |
| Server startet nicht innerhalb von 60 s | Protokoll lesen. Häufig: Port belegt (`port` ändern) oder falsches `package` für den Treiber. |
| Profil fehlt in der Modellliste | Die GGUF-Datei fehlt in `modelsDir`; `Start-Server.ps1` gibt dazu eine Warnung aus. Siehe [modelle.md](modelle.md). |
| Modell lädt nicht (Zustand bleibt `loading` oder fällt auf `unloaded`) | Im Protokoll nach `error` suchen. Meist reicht der GPU-Speicher nicht: andere Programme schließen oder `ctx-size` senken. |
| Fehler `model limit reached, try again later` | Das neue Modell passt nur, wenn ein anderes entladen wird, und dieses bearbeitet gerade eine Anfrage. Ein Modell in Benutzung wird nie entladen. Warten, oder die andere Sitzung beenden. Prüfen: `curl "http://127.0.0.1:8080/slots?model=<profil>"` (`is_processing`). |
| Deutlich langsamer als erwartet | Teile des Modells liegen im Arbeitsspeicher. `Test-Model.ps1` zeigt den GPU-Speicher; `tensor-split` oder `ctx-size` des Profils anpassen. |
| Fehler `System message must be at the beginning` | Das Modell nutzt seine eingebaute Chat-Vorlage. Dem Profil `chat-template-file` geben, siehe [modelle.md](modelle.md). |
| Fehler 500 `A tool message must follow an assistant or tool message`, Claude Code wiederholt die Anfrage mehrfach | Wie oben: eingebaute Chat-Vorlage ohne den Block „agent fix“. Tritt auf, sobald ein Tool-Ergebnis zusammen mit Text ankommt, etwa nach dem Lesen eines Bildes. [modelle.md](modelle.md), Abschnitt „Chat-Vorlage“. |
| Modell erkennt Bilder nicht oder liest sie falsch | `Test-Model.ps1` ausführen. `image input: not configured`: dem Profil fehlt `mmproj`. Warnung beim Start: die `mmproj`-Datei fehlt in `modelsDir`. Falsch gelesene kleine Bilder: `image-min-tokens` erhöhen. |
| GPU-Speicher bleibt nach `exit` belegt | Eine andere Sitzung von `claude-local` läuft noch (die Abschlusszeile nennt den Grund), `onExit` steht auf `keep`, oder das Fenster wurde geschlossen. Dann greift die Leerlauf-Grenze; sofort frei mit `Stop-Server.ps1`. |
| Continue meldet Verbindungsfehler | Server läuft nicht: `scripts\Start-Server.ps1`. |
| Fehler 401 `Invalid API Key` | Der Aufrufer schickt keinen oder einen alten Schlüssel. Continue: `scripts\Install-Continue.ps1` und VS Code neu starten. Eigene Aufrufe: Schlüssel aus `E:\LlamaCpp\run\api-key.txt` mitschicken, siehe „Schnittstellen“. Läuft noch ein Server von vor einer Änderung am Schlüssel: `Restart-Server.ps1`. |
| Ein Skript scheitert an einer Konfigurationsdatei | `scripts\Test-Setup.ps1` nennt die Datei und die Stelle, die nicht passt. |
| Antwort endet nie, das Modell ruft immer weiter Werkzeuge auf | Das Modell schreibt am Ende ein offenes `<tool_call>`, und die Grammatik von llama.cpp erzwingt daraus einen vollständigen Aufruf. Betraf qwen3-coder 30B; anderes Modell nehmen ([modellwahl.md](modellwahl.md)). |

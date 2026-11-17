# Einrichtung

Installation auf einem Windows-Rechner, was der Installer dabei tut, die Werte des
Rechners in `config\machine.json` und welche Datei was einstellt. Der englische
Schnellstart für Nutzer steht oben in der [README](../README.md).

## Voraussetzungen

- 64-Bit Windows 10 (1809) oder Windows 11.
- **Grafikkarte:** NVIDIA mit aktuellem Treiber ist der erprobte Weg. Bei älterem Treiber
  nimmt der Installer das CUDA-12.4-Paket. AMD und Intel laufen über Vulkan:
  **experimentell, nicht getestet**. Ohne Grafikkarte läuft das Modell auf dem Prozessor,
  sehr langsam.
- **Hauptspeicher:** 16 GB ab 26 GB Grafikspeicher, sonst 32 GB, weil dann Teile des
  Modells im Arbeitsspeicher liegen.
- **Platz:** etwa 2 GB für llama.cpp und 17 bis 22 GB je Modell.
- **Internet** für die Installation. Danach läuft alles ohne Netz.
- Claude Code und Git for Windows bringt der Installer nach Rückfrage mit. Python braucht
  nur der Benchmark, VS Code nur Continue.

## Installieren

| Weg | Vorgehen |
|---|---|
| Einzeiler | in PowerShell `irm https://raw.githubusercontent.com/MD220411/Unzensiert/main/install.ps1 \| iex` |
| ZIP | [ZIP laden](https://github.com/MD220411/Unzensiert/archive/refs/heads/main.zip), entpacken, Doppelklick auf `Install.cmd` |
| Git | `git clone https://github.com/MD220411/Unzensiert`, dann `Install.cmd` |

Der Einzeiler (`install.ps1`) legt das Programm nach `%LOCALAPPDATA%\Programs\claude-local`.
Ist Git da, klont er das Repository, sonst lädt er das ZIP. Danach startet er
`scripts\Install.ps1`. Er läuft in der PowerShell-Sitzung des Nutzers und beendet sie nie
(`Test-Install.ps1` prüft, dass er kein `exit` enthält).

Meldet Windows bei `Install.cmd` „Der Computer wurde durch Windows geschützt“, liegt das an
der Herkunft aus dem Internet: „Weitere Informationen“, dann „Trotzdem ausführen“.

### Was der Installer tut

`scripts\Install.ps1` arbeitet sieben Schritte ab und fragt, bevor er etwas installiert
oder lädt. Enter nimmt jeweils den Vorschlag.

| Schritt | Inhalt |
|---|---|
| 1. Rechner prüfen | Windows-Version, Grafikkarten (`nvidia-smi`, Grafikadapter von Windows), Hauptspeicher |
| 2. Installationsordner | Vorschlag: `claude-local` auf dem Laufwerk mit dem meisten Platz, auf dem Systemlaufwerk `%LOCALAPPDATA%\claude-local`. Nie ein ganzes Laufwerk, nie im Programmordner. Ein früher gewählter Ordner bleibt. |
| 3. Claude Code, Git | Claude Code mit dem offiziellen Befehl von Anthropic (`irm https://claude.ai/install.ps1 \| iex`, in eigenem Prozess), Git for Windows über `winget`. Ohne Git bekommt der Agent das Werkzeug PowerShell statt Bash ([agent.md](agent.md)). |
| 4. llama.cpp | `Install-LlamaCpp.ps1`: Paket nach Grafikkarte (`packages` in `config\server.json`). Danach prüft er mit `llama-server --list-devices`, ob llama.cpp die Karte sieht; wenn nicht, nimmt er das nächste Paket ([backend.md](backend.md)). |
| 5. Modell | Stufe aus `config\setups.json` nach Grafikspeicher (Summe aller Karten ohne integrierte Grafik) und Hauptspeicher, siehe unten. Download mit `Get-Model.ps1`. Danach berechnet `Plan-Models.ps1 -Verify` die Verteilung auf Karten und Hauptspeicher und prüft sie ([planer.md](planer.md)); scheitert das, verteilt llama.cpp selbst (`--fit`). Ein vorhandener Plan bleibt. |
| 6. Befehl | `bin\` in den PATH des Benutzers (`Install-Path.ps1`) |
| 7. Test | `Test-Setup.ps1` (nur Fehler werden gezeigt), dann `Test-Model.ps1 -NoLog`, falls der Planer das Modell nicht schon getestet hat |

| Schalter | Wirkung |
|---|---|
| `-Plan` | zeigt nur, was passieren würde: installiert, lädt und ändert nichts (arbeitet auf einer Kopie von `machine.json`) |
| `-Yes` | nimmt jeden Vorschlag ohne Frage; nötig, wenn keine Person am Terminal sitzt |
| `-InstallRoot D:\ki` | dieser Installationsordner |
| `-Model local-fast` | dieses Modell statt des vorgeschlagenen |

Der Installer ist **wiederholbar**. Ein zweiter Lauf repariert: Er überspringt, was schon
da ist, setzt einen abgebrochenen Download fort und lässt Werte in `machine.json` stehen.
Bricht er ab, sagt er warum. Dann einfach neu starten.

**Downloads.** `Get-Model.ps1` lädt die Dateien eines Profils so, wie sie unter `download`
in `config\models.json` stehen: Hugging-Face-Repository mit festem Stand (Commit), Größe
und SHA-256. Eine Datei entsteht als `<name>.part` und bekommt ihren Namen erst, wenn
Größe und Prüfsumme stimmen. Eine Datei unter ihrem richtigen Namen ist also immer
vollständig. `Get-Model.ps1 -List` zeigt alle Profile mit Größe und Stand,
`-Verify` prüft vorhandene Dateien erneut.

### Hardware-Stufen

`config\setups.json` ordnet dem Grafikspeicher ein Modell und eine Kontextgröße zu. Die
erste Stufe, deren Bedarf der Rechner erfüllt, wird vorgeschlagen. Wie das Modell dann auf
Karten und Hauptspeicher verteilt wird und welcher Kontext tatsächlich gilt, berechnet der
Planer für den einzelnen Rechner ([planer.md](planer.md)); die Kontextgröße der Stufe gilt
nur, wenn er scheitert. Die Messwerte unten stammen aus Läufen, in denen llama.cpp selbst
verteilte (`--fit`); die Werte mit Planer stehen in [planer.md](planer.md).

| Grafikspeicher | Hauptspeicher | Modell | Kontext | Gemessen auf | Antwort | Sitzungsbeginn |
|---|---|---|---|---|---|---|
| ab 26 GB | 16 GB | `local-coder` (Qwen 3.6 27B) | 128k | RTX 5070 Ti + RTX 3060 | 44 Tokens/s (mit eigener Aufteilung etwa 60) | 32 s |
| ab 22 GB | 16 GB | `local-coder` | 64k | beide Karten, auf etwa 23 GB begrenzt | 49 Tokens/s | 30 s |
| ab 15 GB | 32 GB | `local-coder`, teils im Hauptspeicher | 64k | RTX 5070 Ti allein | 21 Tokens/s | 46 s |
| ab 11 GB | 32 GB | `local-fast` (Qwen 3.6 35B-A3B), teils im Hauptspeicher | 64k | RTX 3060 allein | 62 Tokens/s | 107 s |
| ab 7 GB | 32 GB | `local-fast`, großteils im Hauptspeicher | 64k | RTX 3060, 4 GB frei gehalten | 57 Tokens/s | 126 s |
| darunter | 32 GB | `local-fast` auf dem Prozessor | 32k | Core i9-14900K | 26 Tokens/s | 354 s |

Gemessen am 2026-11-17 mit `scripts\Measure-Setup.ps1`: Das Skript zeigt llama.cpp nur
die gewählten Karten (`CUDA_VISIBLE_DEVICES`), hält auf Wunsch Speicher frei
(`--fit-target`) und nimmt die allgemeinen Einstellungen ohne die Feinabstimmung des
Entwicklungsrechners. „Antwort“ ist das Tempo von `Test-Model.ps1`, „Sitzungsbeginn“ die
Zeit, in der das Modell die rund 26.000 Tokens liest, die Claude Code zuerst schickt. Alle
Läufe bestanden Tool-Calls und Bild-Eingabe. Rohwerte: `logs\model-tests.log`.

- **16 GB: `local-coder` statt `local-fast`.** Auf der RTX 5070 Ti allein antwortet
  `local-fast` mit 97 Tokens/s, `local-coder` nur mit 21. Im Benchmark löste `local-coder`
  aber 14 von 15 der schweren Aufgaben, `local-fast` 3 von 15 (Stand vor der
  Abschlussprüfung, [modellwahl.md](modellwahl.md)). Zuverlässigkeit geht vor. Der
  Installer nennt `local-fast` als Alternative (`-Model local-fast`).
- **12 GB: `local-fast`.** `local-coder` antwortet auf der RTX 3060 allein mit 11 Tokens/s
  und braucht 143 s für den Sitzungsbeginn; das ist für die Arbeit zu zäh.
- **Grenzen der Messung.** Eine Karte allein steht für einen Rechner mit dieser Karte; eine
  echte Karte derselben Größe kann schneller oder langsamer sein (Speicherbandbreite,
  PCIe). Die 22-GB- und 8-GB-Stufen sind nachgestellt, nicht auf solchen Karten gemessen.
  Den Bedarf an Hauptspeicher zeigt dieser Rechner (128 GB) nicht verlässlich: Windows
  zählt die eingeblendete Modelldatei mit. Die Mindestwerte (16 GB, mit Auslagerung 32 GB)
  sind daher Schätzungen; der Modellprozess belegte bei Auslagerung 11 bis 20 GB privat.

## Werte dieses Rechners: `config\machine.json`

Die Dateien in `config\` gelten auf jedem Rechner und stehen im Repository.
`config\machine.json` hält, was nur für diesen Rechner gilt, und steht nicht im
Repository (`.gitignore`). Der Installer legt sie an. Ein Abschnitt überschreibt die Datei
gleichen Namens:

| Abschnitt | überschreibt | Beispiel |
|---|---|---|
| `server` | `server.json` | `installRoot`, `package` |
| `projects` | `projects.json` | `projectsRoot` |
| `agent` | `agent.json` | `model` (Standardmodell dieses Rechners) |
| `benchmark` | `benchmark.json` | `workDir` |
| `modelDefaults` | `defaults` in `models.json` | `gpu-layers` |
| `models` | ein Profil in `models.json` | `args` (Aufteilung, Karte, Kontext), `file` |

Objekte werden Schlüssel für Schlüssel zusammengeführt, `null` entfernt einen Schlüssel.
Pfade dürfen `%VARIABLEN%` enthalten. Dazu kommen die Abschnitte `plans` und
`calibration` des Planers ([planer.md](planer.md)) und `planner` (überschreibt
`config\planner.json`). So sieht die Datei auf dem Entwicklungsrechner aus (RTX 5070 Ti +
RTX 3060, Verteilung berechnet):

```json
{
  "server": { "installRoot": "E:\\LlamaCpp", "package": "win-cuda-13.5-x64" },
  "projects": { "projectsRoot": "E:\\Projekte" },
  "agent": { "model": "local-coder" },
  "models": {
    "local-coder": { "args": { "ctx-size": 131072, "fit": "off", "gpu-layers": 66,
                               "device": "CUDA1,CUDA0", "tensor-split": "29,37",
                               "mmproj-offload": false } },
    "qwen2.5-coder-1.5b-base": { "file": "qwen2.5-coder-1.5b-base-Q4_K_M.gguf", "args": { "device": "CUDA1" } }
  },
  "plans": { "local-coder": { "ctx": 131072, "predictedTokensPerSecond": 28, "measuredTokensPerSecond": 70.7 } },
  "calibration": { "local-coder": { "speed": { "Host": 19.89, "CUDA0": 1.38, "CUDA1": 3.57 } } }
}
```

Von Hand ändern ist erlaubt. Der Installer behält die Werte, nur fehlende ergänzt er;
`Plan-Models.ps1` überschreibt die Optionen, die es selbst setzt. Danach
`scripts\Restart-Server.ps1`, dann `scripts\Test-Setup.ps1`. Der Wächter fragt nach,
bevor das Modell die Datei ändert ([sicherheit.md](sicherheit.md)).

## Aktualisieren

- **Einzeiler** erneut ausführen. Er holt die neue Version (`git pull` oder das ZIP über
  den Ordner, `machine.json` bleibt) und startet den Installer, der nur Neues nachholt.
  Wurden Dateien im Programmordner von Hand geändert, aktualisiert er nicht und sagt das.
- **Git-Klon:** `git pull`, dann `Install.cmd`.
- **Neue llama.cpp-Version:** `build` in `config\server.json`, dann `Install-LlamaCpp.ps1`
  ([backend.md](backend.md)).

## Deinstallieren

`Uninstall.cmd` bzw. `scripts\Uninstall.ps1` fragt vor jedem Teil:

1. Server stoppen.
2. `bin\` aus dem PATH nehmen.
3. Das Erscheinungsbild „Nachtschicht“ zurücknehmen, falls es installiert ist.
4. Im Installationsordner nur löschen, was der Installer angelegt hat: llama.cpp-Ordner
   (`b<Nummer>` mit `llama-server.exe`), die Dateien der Profile aus `models.json`, `run`,
   `logs`, `downloads`, `bench-work`. Andere Dateien bleiben und mit ihnen der Ordner.
   `-KeepModels` behält die Modelle.
5. `config\machine.json` löschen.

Claude Code, Git for Windows und die Einstellungen von Continue bleiben. Wie man sie
entfernt, zeigt das Skript am Ende. Den Programmordner löscht man danach von Hand.

## Welche Datei stellt was ein

| Datei | Inhalt | Beschreibung |
|---|---|---|
| `config\server.json` | llama-server: Version, Pakete je Grafikkarte, Adresse, Grenzen | [backend.md](backend.md) |
| `config\models.json` | Modellprofile: Datei, Download, Kontext, Sampling | [modelle.md](modelle.md) |
| `config\setups.json` | Hardware-Stufen: welches Modell für wie viel Grafikspeicher | oben |
| `config\machine.json` | Werte dieses Rechners, vom Installer, nicht im Repository | oben |
| `config\templates\*.jinja` | angepasste Chat-Vorlagen | [modelle.md](modelle.md) |
| `config\agent.json` | Claude Code: Standardmodell, Kurznamen, Auswahl, Regeln | [agent.md](agent.md) |
| `config\entwicklungsregeln.md` | Arbeitsregeln für das lokale Modell | [agent.md](agent.md) |
| `config\continue.config.yaml` | Continue: Chat- und Autocomplete-Modelle | unten |
| `config\benchmark.json` | Profile und Aufgaben des Benchmarks | [erweitern.md](erweitern.md) |
| `config\guard.json` | Schutzregeln für Werkzeug-Aufrufe des lokalen Modells | [sicherheit.md](sicherheit.md) |

## Continue (Chat und Autocomplete im Editor)

`scripts\Install-Continue.ps1` installiert die Erweiterung, kopiert
`config\continue.config.yaml` nach `%USERPROFILE%\.continue\config.yaml` (eine vorhandene,
abweichende Datei wird gesichert), trägt dabei den Schlüssel des Servers ein und prüft, dass
jedes genannte Modell ein Profil ist. Nach einem neuen Schlüssel das Skript erneut
ausführen. Das Autocomplete-Modell lädt `Get-Model.ps1 -Model qwen2.5-coder-1.5b-base`.

- Chat nutzt `local-coder` oder `local-fast` über die OpenAI-kompatible Schnittstelle.
- Autocomplete nutzt `qwen2.5-coder-1.5b-base` über die Schnittstelle `/completion`. Auf
  dem Entwicklungsrechner liegt das Modell allein auf der RTX 3060 (`machine.json`) und
  passt neben jedes der großen Modelle.
- Der Server muss laufen (`scripts\Start-Server.ps1`).
- Stand 2026-11-15: Die Schnittstellen sind mit direkten Anfragen geprüft, die Bedienung
  in VS Code selbst nach dem Umbau auf llama.cpp noch nicht, auch nicht mit dem Schlüssel
  des Servers. Meldet Continue Fehler 401, schickt es den Schlüssel nicht mit
  ([backend.md](backend.md), Fehlersuche).

## Was von Ollama übrig ist

Auf dem Entwicklungsrechner nichts. Bis 2026-11-14 lief das Projekt über Ollama; am selben
Tag wurde Ollama deinstalliert:

- Programm, Modellordner `E:\Ollama` (64 GB) und `%USERPROFILE%\.ollama` sind entfernt,
  ebenso der Autostart-Eintrag von Ollama.
- Die Benutzer-Variablen `OLLAMA_*` und `LLAMA_ARG_TENSOR_SPLIT` sind gelöscht.
- Die damals übernommenen GGUF-Dateien lagen als Hardlinks in `E:\LlamaCpp\models` und
  sind erhalten geblieben.

Die alten Skripte und Einstellungen stehen in der Git-Historie vor der ersten öffentlichen Version (bis Commit `fbb8c80`, nicht veröffentlicht).

## Autostart

`llama-server` startet nicht mit Windows. Es gibt keinen Dienst, keinen Autostart-Eintrag
und keine geplante Aufgabe. Der Server läuft erst, wenn `claude-local` oder
`scripts\Start-Server.ps1` ihn startet, und bis `scripts\Stop-Server.ps1` oder zum
Abmelden.

## Fehlersuche

Backend: [backend.md](backend.md). Agent: [agent.md](agent.md). Darüber hinaus:

| Symptom | Ursache und Abhilfe |
|---|---|
| `Install stopped: ...` | Die Meldung nennt den Grund. Behoben? Installer neu starten, er macht dort weiter. |
| `No llama.cpp package could use the graphics card` | Treiber zu alt oder Karte nicht unterstützt. Treiber aktualisieren, Installer neu starten. |
| `Not enough disk space` | Anderen Installationsordner wählen (`-InstallRoot`) oder Platz schaffen. |
| `claude-local` wird nicht gefunden | Neues Terminal öffnen (der PATH gilt erst dort). Sonst `scripts\Install-Path.ps1` ausführen. |
| `no model is installed yet` | Installer erneut starten oder `scripts\Get-Model.ps1 -Model <name>`. |
| Agent bearbeitet keine Dateien, schreibt nur Text | Modell beherrscht keine Tool-Calls. `Test-Model.ps1 -Model <name>` muss `tool calling: OK` zeigen. |
| Agent vergisst den Anfang der Sitzung | Kontext voll. Neue Sitzung oder `/clear`. |
| Skript bricht mit Zeichensalat in Meldungen ab | Eine `.ps1`-Datei enthält Nicht-ASCII-Zeichen. Windows PowerShell 5.1 liest Dateien ohne BOM als ANSI. |

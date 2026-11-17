# Lokaler Coding-Agent

**claude-local** runs [Claude Code](https://code.claude.com) with an open, uncensored model
on your own graphics card instead of the Anthropic cloud: no token limit, and your code
never leaves your machine. [llama.cpp](https://github.com/ggml-org/llama.cpp) runs the
model. Your normal `claude` keeps working as before.

*Deutsch: Claude Code mit einem lokalen, unzensierten Modell auf der eigenen Grafikkarte.
Die ausführliche Dokumentation ist deutsch und beginnt bei [Benutzen](#benutzen).*

## Quick start

**You need** 64-bit Windows 10 (1809) or 11, a graphics card with 12 GB or more (NVIDIA;
AMD and Intel are experimental), 32 GB of main memory, about 25 GB of free disk space and
an internet connection for the install.

**Install.** Open PowerShell (Start menu, type "PowerShell") and paste:

```powershell
irm https://raw.githubusercontent.com/MD220411/Unzensiert/main/install.ps1 | iex
```

Or download the [ZIP](https://github.com/MD220411/Unzensiert/archive/refs/heads/main.zip),
unpack it and double-click **Install.cmd**. If Windows says "Windows protected your PC",
click "More info", then "Run anyway".

The installer looks at your machine and asks before it installs or downloads anything:

| Step | What happens |
|---|---|
| 1 | checks Windows, graphics cards and main memory |
| 2 | picks an install folder for llama.cpp, models and logs (the drive with the most free space) |
| 3 | installs Claude Code (Anthropic's official installer) and Git for Windows, if they are missing |
| 4 | installs llama.cpp in the build that fits your graphics card |
| 5 | downloads the model that fits your graphics memory (17 to 22 GB from Hugging Face, checked by SHA-256) |
| 6 | sets up the command `claude-local` |
| 7 | runs a short test |

**Use.** Open a new terminal window in your project folder and type:

```
claude-local
```

The first start of Claude Code asks for a colour theme and whether you trust the folder.
No Anthropic account is needed for the local model. Inside a session, `/model` switches
between the models you have installed. More models: `scripts\Get-Model.ps1 -List`.

**Which model you get** depends on the graphics memory (all cards added up,
`config\setups.json`):

| Graphics memory | Model | Context | Measured on | Answer speed | Session start |
|---|---|---|---|---|---|
| 26 GB or more | `local-coder` (Qwen 3.6 27B) | 128k | RTX 5070 Ti + RTX 3060 | 44 tokens/s (60 tuned) | 32 s |
| 22 GB or more | `local-coder` | 64k | both cards limited to about 23 GB | 49 tokens/s | 30 s |
| 15 GB or more | `local-coder`, partly in main memory | 64k | RTX 5070 Ti alone | 21 tokens/s | 46 s |
| 11 GB or more | `local-fast` (Qwen 3.6 35B-A3B), partly in main memory | 64k | RTX 3060 alone | 62 tokens/s | 107 s |
| 7 GB or more | `local-fast`, mostly in main memory | 64k | RTX 3060 with 4 GB kept free | 57 tokens/s | 126 s |
| no usable card | `local-fast` on the processor | 32k | Core i9-14900K | 26 tokens/s | 354 s |

"Session start" is how long the model needs to read the roughly 26,000 tokens Claude Code
sends first. `local-fast` answers faster but solves hard tasks less reliably; on 16 GB it
runs at 97 tokens/s (`-Model local-fast` when installing). The cards were measured alone by
hiding the others from llama.cpp; a real card of that size can be faster or slower.

**Update:** run the install line again. **Remove:** double-click **Uninstall.cmd**; it
asks before deleting anything and leaves Claude Code and Git in place.

**Good to know**

- Claude Code is Anthropic's program and comes from Anthropic's own installer;
  claude-local only starts it with a local model.
- The models are uncensored: they do not refuse requests. A guard protects your machine
  instead: it blocks commands that would destroy data (formatting a drive, deleting your
  user folder) and asks you before sensitive ones ([docs/sicherheit.md](docs/sicherheit.md)).
- A local 27B model is much weaker than Claude. Small features, changes across a few
  files and bug hunting go well; see [Grenzen](#grenzen).
- Tested on Windows 11 with an RTX 5070 Ti and an RTX 3060. On other hardware it has not
  run yet: please open an issue and tell what worked and what did not.

## Benutzen

In einem Terminal (auch im VS-Code-Terminal) im gewünschten Projektordner:

```
claude-local
```

Das startet Claude Code mit dem Standardmodell dieses Rechners (vom Installer passend zum
Grafikspeicher gewählt, auf großen Karten `local-coder`). Der Server wird bei Bedarf
mitgestartet; das Modell lädt bei der ersten Anfrage (etwa 10 bis 60 Sekunden). Endet die
letzte Sitzung, wird das Modell entladen und der GPU-Speicher ist wieder frei.

| Befehl | Wirkung |
|---|---|
| `claude-local` | Sitzung mit dem Standardmodell (`local-coder`, unzensiert) |
| `claude-local -Model schnell` | `local-fast` (Qwen 3.6 35B-A3B, unzensiert): etwa doppelt so viele Tokens pro Sekunde, bei schwereren Aufgaben weniger zuverlässig |
| `claude-local -Model qwen38` | `local-qwen38` (Qwen 3.8 27B, unzensiert): früheres Standardmodell, zum Vergleich |
| `claude-local -Model unzensiert` | ausdrücklich `local-coder` |
| `/model` in einer Sitzung | zwischen „Unzensiert“, „Schnell“ und „Qwen 3.8“ wechseln, ohne die Sitzung zu beenden |
| `claude-local -p "Frage"` | einmalige Antwort ohne Sitzung |
| `claude-local -OnExit keep` | Modell nach der Sitzung geladen lassen |
| `claude` | wie bisher: Anthropic-Cloud |

Alle weiteren Argumente gehen unverändert an Claude Code.

Das lokale Modell bekommt in jeder Sitzung feste Arbeitsregeln für pflegbare Software
(Struktur vor Code, Module, Dokumentation, Tests): `config\entwicklungsregeln.md`.

Bevor das Modell eine Aufgabe als erledigt meldet, läuft eine Abschlussprüfung: der
Prüfbefehl des Projekts, falls es einen hat, eine Erinnerung an Test, README und
Einstellungen und nach größeren Änderungen in einem Git-Projekt ein zweiter Blick:
`local-qwen38` prüft den Diff in frischem Kontext, gefundene Fehler gehen an das Modell
zurück ([docs/agent.md](docs/agent.md)).

| Befehl in der Sitzung | Ablauf |
|---|---|
| `/lokal:feature <Beschreibung>` | neue Funktion: Abnahmekriterien, Plan, Tests, Code, Prüfung, Dokumentation |
| `/lokal:bugfix <Fehler>` | erst ein Test, der den Fehler zeigt, dann die Korrektur |
| `/lokal:pruefen` | die letzten Änderungen prüfen, ohne etwas zu ändern |

Ein neues Projekt mit fester Struktur (README, `CLAUDE.md`, Tests, Konfiguration,
Prüfbefehl, Git) legt `scripts\New-Project.ps1 -Name <name>` an
([docs/projekte.md](docs/projekte.md)). Fakten von außen (Pins, Spannungen, fremde
Schnittstellen) stehen dort einmal mit Quelle in `facts\facts.json`; der Prüfbefehl meldet
jede Stelle in Doku und Code, die davon abweicht.

Ein Wächter prüft jeden Befehl des Modells, bevor er läuft: Was den Rechner oder die
eigenen Daten zerstören würde, ist gesperrt, bei Heiklem wirst du gefragt, normale Arbeit
im Projektordner bleibt frei ([docs/sicherheit.md](docs/sicherheit.md)).

Bilder (Screenshots, Skizzen) liest das Modell ebenfalls: mit Alt+V einfügen, die Datei ins
Terminal ziehen oder den Pfad nennen.

### Autocomplete und Chat im Editor

Die VS-Code-Erweiterung **Continue** schlägt beim Tippen Code vor (Tab übernimmt) und bietet
in der Seitenleiste einen Chat mit `local-coder` oder `local-fast`. Einrichtung:
`scripts\Install-Continue.ps1`. Der Server muss dafür laufen: `scripts\Start-Server.ps1`.

## Stand

| | |
|---|---|
| Modell | `local-coder` = Qwen 3.6 27B, unzensiert (Heretic v2), mit MTP, 128k Kontext |
| Tempo | `local-coder` etwa 60 Tokens/s, `local-fast` 83 bis 140; beide vollständig auf den Grafikkarten (RTX 5070 Ti + RTX 3060) |
| Benchmark | `local-coder`: alle 24 Läufe der vier älteren Aufgaben bestanden, 14 von 15 der fünf schwereren, 89 % der Arbeitsregeln eingehalten, mit Projektvorlage 91 % (gemessen mit 64k); die zwei Aufgaben zu Faktentreue und Konsistenz über Dateien 6 von 6. `local-fast` (Stand vor der Abschlussprüfung): 3 von 15, 52 % ([modellwahl.md](docs/modellwahl.md)) |
| Backend | llama.cpp Build b12433 (`llama-server` im Router-Modus), Programme und Modelle im Installationsordner (`config\machine.json`) |
| Installation | Installer für jeden Windows-Rechner: wählt llama.cpp-Paket und Modell nach Grafikkarte, lädt mit Prüfsumme ([einrichtung.md](docs/einrichtung.md)); erprobt nur auf diesem Rechner |
| Agent | Claude Code über die Anthropic-kompatible Schnittstelle von `llama-server` |

## Grenzen

- Ein lokales 27B-Modell ist deutlich schwächer als Claude. Kleine Features, Erweiterungen,
  Umbauten über einige Dateien, Fehlersuche und PowerShell-Skripte gehen gut. README und
  Tests entstehen zuverlässig erst durch die Abschlussprüfung; sie kostet etwa ein Viertel
  mehr Zeit je Aufgabe (gemessen, [modellwahl.md](docs/modellwahl.md)).
- Auch 128k Kontext werden voll. Claude Code komprimiert dann die Unterhaltung. Für neue
  Aufgaben besser eine neue Sitzung starten (`/clear`). Eine Aufgabe, die viele Dateien auf
  einmal braucht, kann mit „Autocompact is thrashing“ abbrechen; dann in Teilen beauftragen.
- Connectors von claude.ai und Cloud-Funktionen sind im lokalen Modus aus.

## Aufbau

```
Install.cmd   Installieren oder reparieren (Doppelklick), Uninstall.cmd entfernt wieder
install.ps1   Einzeiler-Installation: holt das Repository und startet scripts\Install.ps1
bin\          Befehl claude-local für den PATH
config\       alle Einstellungen: server.json, models.json, agent.json, setups.json, Regeln, Vorlagen;
              machine.json = Werte dieses Rechners (vom Installer, nicht im Repository)
scripts\      ein Skript je Aufgabe; gemeinsame Bausteine in scripts\lib\
benchmark\    Aufgaben für den Agenten-Benchmark
templates\    Vorlagen für neue Projekte
tests\        Prüffälle für die Skripte
docs\         Dokumentation
logs\         Messergebnisse
```

Programme, Modelldateien und das Server-Protokoll liegen außerhalb des Repositorys im
Installationsordner, den der Installer wählt (Vorschlag: `claude-local` auf dem Laufwerk
mit dem meisten Platz).

## Dokumentation

| Datei | Inhalt |
|---|---|
| [docs/architektur.md](docs/architektur.md) | Schichten, Ordner, Grundsätze, Begründungen |
| [docs/einrichtung.md](docs/einrichtung.md) | Installer Schritt für Schritt, Hardware-Stufen, Aktualisieren, Deinstallieren, Werte des Rechners (`machine.json`), Überblick der Konfigurationsdateien |
| [docs/backend.md](docs/backend.md) | llama-server: bedienen, einstellen, aktualisieren, Fehlersuche |
| [docs/modelle.md](docs/modelle.md) | Modellprofile, MTP, Chat-Vorlage, neues Modell aufnehmen |
| [docs/agent.md](docs/agent.md) | `claude-local`, Modellauswahl, Arbeitsregeln, Abschlussprüfung, zweiter Blick, Befehle für feste Abläufe |
| [docs/projekte.md](docs/projekte.md) | neues Projekt aus der Vorlage, Prüfbefehl, Fakten mit Quelle und Abgleich gegen Doku und Code, Arbeitsweise in einem Projekt |
| [docs/stil.md](docs/stil.md) | Erscheinungsbild: „Ausbruch“ (bunt, Bilder aus Zeichen) oder „Nachtschicht“ (ruhig); Shell, Statuszeile, Farbthemen für `claude` und `claude-local`, Stil wechseln |
| [docs/erweitern.md](docs/erweitern.md) | Wegweiser für Änderungen, Benchmark, neue Skripte |
| [docs/modellwahl.md](docs/modellwahl.md) | Bewertung der Messwerte und Empfehlung |
| [docs/benchmark.md](docs/benchmark.md) | Messwerte aller getesteten Modelle (automatisch erzeugt) |
| [docs/gpu-tuning.md](docs/gpu-tuning.md) | Aufteilung auf die beiden Grafikkarten, Rolle von PCIe x4 |
| [docs/gpu-setups.md](docs/gpu-setups.md) | Messwerte je GPU-Aufteilung (Stand Ollama, 2026-11-13) |
| [docs/sicherheit.md](docs/sicherheit.md) | Schutz des eigenen Rechners: Schlüssel für den Server, Wächter vor jedem Werkzeug-Aufruf, Git-Hinweis, Prüfskripte |
| [docs/roadmap.md](docs/roadmap.md) | Zukunftsplan: Vorschläge zu Sicherheit, Qualität, nachhaltiger Entwicklung, Effizienz und Tempo, mit Reihenfolge |
| [docs/protokoll.md](docs/protokoll.md) | Was wann gemacht und gemessen wurde, offene Punkte |

## Skripte

Aufruf jeweils mit `powershell -ExecutionPolicy Bypass -File scripts\<Name>`.

| Skript | Zweck |
|---|---|
| `Install.ps1` | Installer: Rechner prüfen, Claude Code, Git, llama.cpp, passendes Modell, PATH, Test; `-Plan` zeigt nur, was passieren würde (auch über `Install.cmd`) |
| `Uninstall.ps1` | wieder entfernen, mit Rückfragen; löscht nur, was der Installer angelegt hat (auch über `Uninstall.cmd`) |
| `Install-LlamaCpp.ps1` | llama.cpp in der Version aus `config\server.json` laden, prüfen, entpacken; Paket passend zur Grafikkarte |
| `Get-Model.ps1` | Dateien eines Modellprofils von Hugging Face laden (fortsetzbar, mit SHA-256), `-List` zeigt alle Profile |
| `Add-Model.ps1` | eigene GGUF-Datei in den Modellordner legen (Hardlink oder Kopie) |
| `Start-Server.ps1` | Server starten, Modellprofile anzeigen |
| `Stop-Server.ps1` | Server und alle Modelle beenden |
| `Restart-Server.ps1` | Neustart, nötig nach Änderungen an `server.json` oder `models.json` |
| `Test-Model.ps1` | Tempo, Tool-Calls, Bild-Eingabe und GPU-Speicher eines Profils prüfen |
| `Test-Setup.ps1` | Konfiguration und Skripte prüfen, ohne ein Modell zu laden (wenige Sekunden) |
| `Test-Install.ps1` | Logik des Installers prüfen, ohne Download und ohne Grafikkarte: `machine.json`, Geräteliste, Wahl der Stufe, Download-Einträge, Probelauf `-Plan` |
| `Test-Guard.ps1` | Schutzregeln gegen die Fälle in `tests\guard-cases.json` prüfen |
| `Test-Tasks.ps1` | Benchmark-Aufgaben prüfen, ohne ein Modell: Vorlage fällt durch, Musterlösung besteht |
| `Test-Templates.ps1` | Projektvorlagen prüfen: neues Projekt besteht seinen Prüfbefehl, eingebaute Fehler (Widerspruch zu `facts\facts.json`, Fakt ohne Quelle, scheiternder Test) lassen ihn scheitern |
| `New-Project.ps1` | neues Projekt aus der Vorlage anlegen (Python oder PowerShell), mit Prüfbefehl und erstem Commit |
| `Invoke-Review.ps1` | zweiter Blick: ein zweites lokales Modell prüft die nicht committete Änderung eines Projekts (läuft auch in der Abschlussprüfung) |
| `Benchmark-Models.ps1` | Profile vergleichen: Rohwerte, Agenten-Aufgaben und eingehaltene Arbeitsregeln |
| `Measure-Setup.ps1` | eine Hardware-Stufe auf diesem Rechner nachstellen und messen (nur bestimmte Karten sichtbar, ohne Feinabstimmung), für `measured` in `config\setups.json` |
| `Install-Path.ps1` | `bin\` in den PATH aufnehmen |
| `Install-Continue.ps1` | Continue installieren und Konfiguration kopieren |
| `Install-Font.ps1` | Schrift des Erscheinungsbilds (IBM Plex Mono) für den Benutzer installieren |
| `Install-Style.ps1` | den in `config\style.json` gewählten Stil (`config\styles\`) auf Windows Terminal und Claude Code anwenden, auch nach einem Wechsel (`-Remove` nimmt es zurück) |
| `claude-local.ps1` | Starter hinter dem Befehl `claude-local` |

## Lizenz

MIT, siehe [LICENSE](LICENSE). Die Chat-Vorlagen in `config\templates\` sind angepasste
Fassungen der Vorlagen aus den Modelldateien und stehen unter der Lizenz des jeweiligen
Modells.

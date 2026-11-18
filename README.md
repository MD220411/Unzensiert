# Lokaler Coding-Agent

**Unzensiert** is a coding agent that runs an open, uncensored model on your own graphics
card: no cloud, no token limit, and your code never leaves your machine.
[llama.cpp](https://github.com/ggml-org/llama.cpp) runs the model. The agent is this
project's own program; it works like Claude Code (same tools, keys and look) and needs
nothing else to be installed. For comparison the same models also run in
[Claude Code](https://code.claude.com) (`claude-local`). New releases install themselves,
unless you switch that off.

*Deutsch: ein eigener Coding-Agent mit einem lokalen, unzensierten Modell auf der eigenen
Grafikkarte, zum Vergleich auch in Claude Code. Die ausführliche Dokumentation ist deutsch
und beginnt bei [Benutzen](#benutzen).*

## Quick start

**You need** 64-bit Windows 10 (1809) or 11, a graphics card with 12 GB or more (NVIDIA;
AMD and Intel are experimental), 32 GB of main memory, about 25 GB of free disk space and
an internet connection for the install.

**Install.** Open PowerShell (Start menu, type "PowerShell") and paste:

```powershell
irm https://raw.githubusercontent.com/MD220411/Unzensiert/main/install.ps1 | iex
```

Or download *Source code (zip)* of the [latest release](https://github.com/MD220411/Unzensiert/releases/latest),
unpack it and double-click **Install.cmd**. If Windows says "Windows protected your PC",
click "More info", then "Run anyway".

The installer looks at your machine and asks before it installs or downloads anything:

| Step | What happens |
|---|---|
| 1 | checks Windows, graphics cards and main memory |
| 2 | picks an install folder for llama.cpp, models and logs (the drive with the most free space) |
| 3 | installs Git for Windows, if it is missing; Claude Code only if you want the comparison command (the question defaults to no) |
| 4 | installs llama.cpp in the build that fits your graphics card |
| 5 | downloads the model that fits your graphics memory (17 to 22 GB from Hugging Face, checked by SHA-256), then measures your cards and computes how to spread the model over them and the main memory, and tests that (one to two minutes) |
| 6 | sets up the commands `unzensiert` and `claude-local` and asks whether new releases may install themselves |
| 7 | runs a short test |

**Use.** Open a new terminal window in your project folder and type:

```
unzensiert
```

Type what you want; Enter sends, Shift+Enter starts a new line, Esc stops the model.
`/help` lists the commands, `/model` switches between the models you have installed,
Shift+Tab switches how much the agent may do without asking (`ask`, `edits`, `all`).
`unzensiert -p "question"` answers once without a session. No account is needed.
More models: `scripts\Get-Model.ps1 -List`. The same models in Claude Code, for
comparison: `claude-local` ([docs/agent.md](docs/agent.md)).

**Updates.** `unzensiert` looks for a new release at most once a day and installs it (only
published releases, never work in progress). Switch it off with `unzensiert --updates off`,
look now with `unzensiert --update`.

**Which model you get** depends on the graphics memory (all cards added up,
`config\setups.json`). **How it is spread** over your cards and main memory is not taken
from a table: the installer measures how fast each card and the main memory are, asks
llama.cpp how much memory each layout needs, and computes the fastest layout and the
largest context that costs at most 15 % speed ([docs/planer.md](docs/planer.md)).

| Graphics memory | Model | Measured on | Layout by llama.cpp alone | Computed layout |
|---|---|---|---|---|
| 26 GB or more | `local-coder` (Qwen 3.6 27B) | RTX 5070 Ti + RTX 3060 | 44 tokens/s, 128k | **66–71 tokens/s**, 128k |
| 22 GB or more | `local-coder` | both cards limited to about 23 GB | 49 tokens/s, 64k | not measured |
| 15 GB or more | `local-coder`, partly in main memory | RTX 5070 Ti alone | 21 tokens/s, 64k | **22 tokens/s** at 64k; it picks 96k at 19 tokens/s |
| 11 GB or more | `local-fast` (Qwen 3.6 35B-A3B), experts partly in main memory | RTX 3060 alone | 62 tokens/s, 64k | **65 tokens/s** at 64k; it picks 128k at 58 tokens/s |
| 7 GB or more | `local-fast`, experts mostly in main memory | RTX 3060 with 4 GB kept free | 57 tokens/s, 64k | 54 tokens/s at 128k |
| no usable card | `local-fast` on the processor | Core i9-14900K | 26 tokens/s, 32k | |

Speeds are answer speeds with the model guessing ahead (MTP); they vary by a few percent
from run to run. Unzensiert sends about 2,800 tokens with the first request of a task;
Claude Code sends about 26,000, which take 30 s to read on the two cards and up to 2 min on
small cards. `local-fast` answers faster but solves hard
tasks less reliably (`-Model local-fast` when installing). The single cards were measured by
hiding the others from llama.cpp; a real card of that size can be faster or slower.

**Update by hand:** run the install line again. **Remove:** double-click
**Uninstall.cmd**; it asks before deleting anything and leaves Claude Code and Git in place.

**Good to know**

- Unzensiert is written in PowerShell, which every Windows has. Claude Code is
  Anthropic's program, comes from Anthropic's own installer and is only needed for the
  comparison command `claude-local`, which starts it with a local model.
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
unzensiert
```

Das startet den eigenen Agenten mit dem Standardmodell dieses Rechners (vom Installer
passend zum Grafikspeicher gewählt, auf großen Karten `local-coder`). Der Server wird bei
Bedarf mitgestartet; das Modell lädt bei der ersten Anfrage (etwa 10 bis 60 Sekunden). Endet
die letzte Sitzung, wird das Modell entladen und der GPU-Speicher ist wieder frei.
Alles zur Bedienung: [docs/unzensiert.md](docs/unzensiert.md).

| Befehl | Wirkung |
|---|---|
| `unzensiert` | Sitzung mit dem Standardmodell (`local-coder`, unzensiert) |
| `unzensiert "Aufgabe"` | Sitzung, die gleich mit dieser Aufgabe beginnt |
| `unzensiert -Model schnell` | `local-fast` (Qwen 3.6 35B-A3B, unzensiert): etwa doppelt so viele Tokens pro Sekunde, bei schwereren Aufgaben weniger zuverlässig |
| `unzensiert -Model qwen38` | `local-qwen38` (Qwen 3.8 27B, unzensiert): früheres Standardmodell, zum Vergleich |
| `/model` in einer Sitzung | zwischen „Unzensiert“, „Schnell“ und „Qwen 3.8“ wechseln, ohne die Sitzung zu beenden |
| `unzensiert -p "Frage"` | einmalige Antwort ohne Sitzung (`--output-format json` für Skripte) |
| `unzensiert -c` | letzte Sitzung in diesem Ordner fortsetzen (`--resume` zum Auswählen) |
| `unzensiert --updates off` | automatische Updates aus (`on` wieder an, `--update` sofort nachsehen) |
| `claude-local` | dieselben Modelle in Claude Code, zum Vergleich ([agent.md](docs/agent.md)) |
| `claude` | wie bisher: Anthropic-Cloud |

| In der Sitzung | Wirkung |
|---|---|
| Enter, Shift+Enter | senden, neue Zeile |
| Esc | Modell anhalten, laufenden Befehl beenden |
| Shift+Tab, `/mode` | Rechte: `ask` (Änderungen und Befehle fragen), `edits` (Dateien ohne Frage), `all` (alles ohne Frage); der Wächter entscheidet immer zuerst |
| Alt+V | Bild aus der Zwischenablage einfügen |
| `!befehl` | selbst einen Befehl ausführen, das Modell sieht ihn |
| `/compact`, `/clear`, `/resume`, `/status`, `/think`, `/init`, `/help`, `/exit` | zusammenfassen, neu anfangen, fortsetzen, Stand, Denken zeigen, `AGENTS.md` schreiben lassen, Hilfe, beenden |

Das lokale Modell bekommt in jeder Sitzung feste Arbeitsregeln für pflegbare Software
(Struktur vor Code, Module, Dokumentation, Tests): `config\entwicklungsregeln.md`.

Bevor das Modell eine Aufgabe als erledigt meldet, läuft eine Abschlussprüfung: der
Prüfbefehl des Projekts, falls es einen hat, eine Erinnerung an Test, README und
Einstellungen und nach größeren Änderungen in einem Git-Projekt ein zweiter Blick:
`local-qwen38` prüft den Diff in frischem Kontext, gefundene Fehler gehen an das Modell
zurück ([docs/agent.md](docs/agent.md)).

| Befehl in der Sitzung | Ablauf |
|---|---|
| `/feature <Beschreibung>` | neue Funktion: Abnahmekriterien, Plan, Tests, Code, Prüfung, Dokumentation |
| `/bugfix <Fehler>` | erst ein Test, der den Fehler zeigt, dann die Korrektur |
| `/pruefen` | die letzten Änderungen prüfen, ohne etwas zu ändern |

In `claude-local` heißen sie `/lokal:feature`, `/lokal:bugfix`, `/lokal:pruefen`; Unzensiert
versteht beide Schreibweisen.

Ein neues Projekt mit fester Struktur (README, `CLAUDE.md`, Tests, Konfiguration,
Prüfbefehl, Git) legt `scripts\New-Project.ps1 -Name <name>` an
([docs/projekte.md](docs/projekte.md)). Fakten von außen (Pins, Spannungen, fremde
Schnittstellen) stehen dort einmal mit Quelle in `facts\facts.json`; der Prüfbefehl meldet
jede Stelle in Doku und Code, die davon abweicht.

Ein Wächter prüft jeden Befehl des Modells, bevor er läuft: Was den Rechner oder die
eigenen Daten zerstören würde, ist gesperrt, bei Heiklem wirst du gefragt, normale Arbeit
im Projektordner bleibt frei ([docs/sicherheit.md](docs/sicherheit.md)).

Bilder (Screenshots, Skizzen) liest das Modell ebenfalls: mit Alt+V einfügen oder den Pfad
nennen.

### Autocomplete und Chat im Editor

Die VS-Code-Erweiterung **Continue** schlägt beim Tippen Code vor (Tab übernimmt) und bietet
in der Seitenleiste einen Chat mit `local-coder` oder `local-fast`. Einrichtung:
`scripts\Install-Continue.ps1`. Der Server muss dafür laufen: `scripts\Start-Server.ps1`.

## Stand

| | |
|---|---|
| Modell | `local-coder` = Qwen 3.6 27B, unzensiert (Heretic v2), mit MTP, 128k Kontext |
| Tempo | `local-coder` 66 bis 71 Tokens/s mit der berechneten Verteilung (vorher etwa 60 von Hand, 44 mit `--fit`), `local-fast` 171 (vorher 83 bis 140), `local-qwen38` 70; alle mit 128k Kontext (RTX 5070 Ti + RTX 3060) ([planer.md](docs/planer.md)) |
| Benchmark | `local-coder`: alle 24 Läufe der vier älteren Aufgaben bestanden, 14 von 15 der fünf schwereren, 89 % der Arbeitsregeln eingehalten, mit Projektvorlage 91 % (gemessen mit 64k); die zwei Aufgaben zu Faktentreue und Konsistenz über Dateien 6 von 6. `local-fast` (Stand vor der Abschlussprüfung): 3 von 15, 52 % ([modellwahl.md](docs/modellwahl.md)) |
| Backend | llama.cpp Build b12433 (`llama-server` im Router-Modus), Programme und Modelle im Installationsordner (`config\machine.json`) |
| Installation | Installer für jeden Windows-Rechner: wählt llama.cpp-Paket und Modell nach Grafikkarte, lädt mit Prüfsumme, misst die Karten und berechnet die Verteilung auf Karten und Hauptspeicher ([einrichtung.md](docs/einrichtung.md), [planer.md](docs/planer.md)); erprobt nur auf diesem Rechner |
| Agent | Unzensiert, eigenes Programm (PowerShell 5.1, OpenAI-kompatible Schnittstelle von `llama-server`), Version in `VERSION`, automatische Updates aus den Releases; zum Vergleich Claude Code über die Anthropic-kompatible Schnittstelle ([unzensiert.md](docs/unzensiert.md)) |
| Vergleich | Unzensiert gegen Claude Code, alle elf Aufgaben je dreimal mit `local-coder`: Unzensiert bei allen elf schneller (Summe der Mediane 1.629 s statt 2.160 s, 36 % weniger Runden); bestanden 27 statt 29 von 33, ein Unterschied im Rahmen des Zufalls (alle Fehlschläge sind Fehler des Modells, die auch bei Claude Code vorkamen); Arbeitsregeln 88 statt 86 von 96 ([modellwahl.md](docs/modellwahl.md)) |

## Grenzen

- Ein lokales 27B-Modell ist deutlich schwächer als Claude. Kleine Features, Erweiterungen,
  Umbauten über einige Dateien, Fehlersuche und PowerShell-Skripte gehen gut. README und
  Tests entstehen zuverlässig erst durch die Abschlussprüfung; sie kostet etwa ein Viertel
  mehr Zeit je Aufgabe (gemessen, [modellwahl.md](docs/modellwahl.md)).
- Auch 128k Kontext werden voll. Unzensiert kürzt dann alte Werkzeugergebnisse und fasst
  die Unterhaltung zusammen, Claude Code komprimiert sie. Für neue Aufgaben besser eine neue
  Sitzung starten (`/clear`). Claude Code kann bei einer Aufgabe, die viele Dateien auf
  einmal braucht, mit „Autocompact is thrashing“ abbrechen; dann in Teilen beauftragen.
- Die Bedienung von Unzensiert im Terminal (Tasten, Fragen) prüfen die Testskripte nur bis
  zur Ausgabe; gemessen sind Einmal-Läufe und der Benchmark.
- Connectors von claude.ai und Cloud-Funktionen sind im lokalen Modus aus.

## Aufbau

```
Install.cmd   Installieren oder reparieren (Doppelklick), Uninstall.cmd entfernt wieder
install.ps1   Einzeiler-Installation: holt das neueste Release und startet scripts\Install.ps1
VERSION       Version des Programms (Releases auf GitHub: Tag vX.Y.Z)
bin\          Befehle unzensiert und claude-local für den PATH
config\       alle Einstellungen: server.json, models.json, agent.json, unzensiert.json, updates.json, setups.json, Regeln, Vorlagen;
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
| [docs/planer.md](docs/planer.md) | Planer: Speicher- und Tempo-Rechnung, Kalibrierung, Suche nach der schnellsten Verteilung, Messwerte, Grenzen |
| [docs/backend.md](docs/backend.md) | llama-server: bedienen, einstellen, aktualisieren, Fehlersuche |
| [docs/modelle.md](docs/modelle.md) | Modellprofile, MTP, Chat-Vorlage, neues Modell aufnehmen |
| [docs/unzensiert.md](docs/unzensiert.md) | der eigene Agent: Bedienung, Tasten, Befehle, Rechte, Werkzeuge, Kontext, gespeicherte Unterhaltungen, Einmal-Lauf, automatische Updates, Releases |
| [docs/agent.md](docs/agent.md) | Einstellungen beider Agenten, Arbeitsregeln, Abschlussprüfung, zweiter Blick, Befehle für feste Abläufe; `claude-local` (Claude Code zum Vergleich) |
| [docs/projekte.md](docs/projekte.md) | neues Projekt aus der Vorlage, Prüfbefehl, Fakten mit Quelle und Abgleich gegen Doku und Code, Arbeitsweise in einem Projekt |
| [docs/stil.md](docs/stil.md) | Erscheinungsbild: „Ausbruch“ (bunt, Bilder und Wand aus Zeichen) oder „Nachtschicht“ (ruhig); Shell, Statuszeile, Farbthemen für `claude` und `claude-local`, Stil wechseln |
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
| `Install.ps1` | Installer: Rechner prüfen, Git (Claude Code nur auf Wunsch), llama.cpp, passendes Modell, PATH, automatische Updates, Test; `-Plan` zeigt nur, was passieren würde (auch über `Install.cmd`) |
| `Uninstall.ps1` | wieder entfernen, mit Rückfragen; löscht nur, was der Installer angelegt hat (auch über `Uninstall.cmd`) |
| `Install-LlamaCpp.ps1` | llama.cpp in der Version aus `config\server.json` laden, prüfen, entpacken; Paket passend zur Grafikkarte |
| `Get-Model.ps1` | Dateien eines Modellprofils von Hugging Face laden (fortsetzbar, mit SHA-256), `-List` zeigt alle Profile |
| `Plan-Models.ps1` | Verteilung jedes Modells auf Karten und Hauptspeicher berechnen (Kalibrierung mit `llama-bench`, Speicher von `llama-fit-params`), in `config\machine.json` schreiben; `-Verify` lädt und testet |
| `Add-Model.ps1` | eigene GGUF-Datei in den Modellordner legen (Hardlink oder Kopie) |
| `Start-Server.ps1` | Server starten, Modellprofile anzeigen |
| `Stop-Server.ps1` | Server und alle Modelle beenden |
| `Restart-Server.ps1` | Neustart, nötig nach Änderungen an `server.json` oder `models.json` |
| `Test-Model.ps1` | Tempo, Tool-Calls, Bild-Eingabe und GPU-Speicher eines Profils prüfen |
| `Test-Setup.ps1` | Konfiguration und Skripte prüfen, ohne ein Modell zu laden (wenige Sekunden) |
| `Test-Install.ps1` | Logik des Installers prüfen, ohne Download und ohne Grafikkarte: `machine.json`, Geräteliste, Wahl der Stufe, Download-Einträge, Probelauf `-Plan`, Planer mit einem nachgebildeten Speichermodell |
| `Test-Guard.ps1` | Schutzregeln gegen die Fälle in `tests\guard-cases.json` prüfen |
| `Test-Agent.ps1` | Agent Unzensiert prüfen, ohne Modell: JSON, Antwortstrom, Werkzeuge, Rechte, Wiederholungen, Sitzungen, Befehle, Abschlussprüfung, Updates, Ausgabe; `-WithModel` löst eine kleine Aufgabe |
| `Test-Tasks.ps1` | Benchmark-Aufgaben prüfen, ohne ein Modell: Vorlage fällt durch, Musterlösung besteht |
| `Test-Templates.ps1` | Projektvorlagen prüfen: neues Projekt besteht seinen Prüfbefehl, eingebaute Fehler (Widerspruch zu `facts\facts.json`, Fakt ohne Quelle, scheiternder Test) lassen ihn scheitern |
| `New-Project.ps1` | neues Projekt aus der Vorlage anlegen (Python oder PowerShell), mit Prüfbefehl und erstem Commit |
| `Invoke-Review.ps1` | zweiter Blick: ein zweites lokales Modell prüft die nicht committete Änderung eines Projekts (läuft auch in der Abschlussprüfung) |
| `Benchmark-Models.ps1` | Profile vergleichen: Rohwerte, Agenten-Aufgaben und eingehaltene Arbeitsregeln; `-Agent unzensiert` oder `claude-local` |
| `Measure-Setup.ps1` | eine Hardware-Stufe auf diesem Rechner nachstellen und messen (nur bestimmte Karten sichtbar, Verteilung durch llama.cpp oder mit `-Planned` durch den Planer), für `measured` in `config\setups.json` |
| `Install-Path.ps1` | `bin\` in den PATH aufnehmen |
| `Install-Continue.ps1` | Continue installieren und Konfiguration kopieren |
| `Install-Font.ps1` | Schrift des Erscheinungsbilds (IBM Plex Mono) für den Benutzer installieren |
| `Install-Style.ps1` | den in `config\style.json` gewählten Stil (`config\styles\`) auf Windows Terminal und Claude Code anwenden, auch nach einem Wechsel (`-Remove` nimmt es zurück) |
| `unzensiert.ps1` | Starter hinter dem Befehl `unzensiert` |
| `claude-local.ps1` | Starter hinter dem Befehl `claude-local` (Claude Code zum Vergleich) |
| `New-Release.ps1` | neue Version veröffentlichen: Prüfungen, `VERSION`, Tag, Release auf GitHub (nur für die Pflege des Repositorys) |

## Lizenz

MIT, siehe [LICENSE](LICENSE). Die Chat-Vorlagen in `config\templates\` sind angepasste
Fassungen der Vorlagen aus den Modelldateien und stehen unter der Lizenz des jeweiligen
Modells.

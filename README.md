# Lokaler Coding-Agent

Claude Code mit einem lokalen, unzensierten Modell statt der Anthropic-Cloud. Läuft ohne
Token-Limit auf den eigenen Grafikkarten, mit llama.cpp als Backend. Das normale `claude`
bleibt unverändert nutzbar.

## Benutzen

In einem Terminal (auch im VS-Code-Terminal) im gewünschten Projektordner:

```
claude-local
```

Das startet Claude Code mit dem Modell `local-coder`. Der Server wird bei Bedarf
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
| Backend | llama.cpp Build b12433 (`llama-server` im Router-Modus), Programme und Modelle in `E:\LlamaCpp` |
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
bin\          Befehl claude-local für den PATH
config\       alle Einstellungen: server.json, models.json, agent.json, Regeln, Vorlagen
scripts\      ein Skript je Aufgabe; gemeinsame Bausteine in scripts\lib\
benchmark\    Aufgaben für den Agenten-Benchmark
templates\    Vorlagen für neue Projekte
tests\        Prüffälle für die Skripte
docs\         Dokumentation
logs\         Messergebnisse
```

Programme, Modelldateien und das Server-Protokoll liegen außerhalb des Repositorys in
`E:\LlamaCpp`.

## Dokumentation

| Datei | Inhalt |
|---|---|
| [docs/architektur.md](docs/architektur.md) | Schichten, Ordner, Grundsätze, Begründungen |
| [docs/einrichtung.md](docs/einrichtung.md) | Neuaufbau auf einem anderen Rechner, Überblick der Konfigurationsdateien |
| [docs/backend.md](docs/backend.md) | llama-server: bedienen, einstellen, aktualisieren, Fehlersuche |
| [docs/modelle.md](docs/modelle.md) | Modellprofile, MTP, Chat-Vorlage, neues Modell aufnehmen |
| [docs/agent.md](docs/agent.md) | `claude-local`, Modellauswahl, Arbeitsregeln, Abschlussprüfung, zweiter Blick, Befehle für feste Abläufe |
| [docs/projekte.md](docs/projekte.md) | neues Projekt aus der Vorlage, Prüfbefehl, Fakten mit Quelle und Abgleich gegen Doku und Code, Arbeitsweise in einem Projekt |
| [docs/stil.md](docs/stil.md) | Erscheinungsbild „Nachtschicht“: Shell, Statuszeile, Farbthemen für `claude` und `claude-local` |
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
| `Install-LlamaCpp.ps1` | llama.cpp in der Version aus `config\server.json` laden, prüfen, entpacken |
| `Add-Model.ps1` | GGUF-Datei in den Modellordner legen (Hardlink oder Kopie) |
| `Start-Server.ps1` | Server starten, Modellprofile anzeigen |
| `Stop-Server.ps1` | Server und alle Modelle beenden |
| `Restart-Server.ps1` | Neustart, nötig nach Änderungen an `server.json` oder `models.json` |
| `Test-Model.ps1` | Tempo, Tool-Calls, Bild-Eingabe und GPU-Speicher eines Profils prüfen |
| `Test-Setup.ps1` | Konfiguration und Skripte prüfen, ohne ein Modell zu laden (wenige Sekunden) |
| `Test-Guard.ps1` | Schutzregeln gegen die Fälle in `tests\guard-cases.json` prüfen |
| `Test-Tasks.ps1` | Benchmark-Aufgaben prüfen, ohne ein Modell: Vorlage fällt durch, Musterlösung besteht |
| `Test-Templates.ps1` | Projektvorlagen prüfen: neues Projekt besteht seinen Prüfbefehl, eingebaute Fehler (Widerspruch zu `facts\facts.json`, Fakt ohne Quelle, scheiternder Test) lassen ihn scheitern |
| `New-Project.ps1` | neues Projekt aus der Vorlage anlegen (Python oder PowerShell), mit Prüfbefehl und erstem Commit |
| `Invoke-Review.ps1` | zweiter Blick: ein zweites lokales Modell prüft die nicht committete Änderung eines Projekts (läuft auch in der Abschlussprüfung) |
| `Benchmark-Models.ps1` | Profile vergleichen: Rohwerte, Agenten-Aufgaben und eingehaltene Arbeitsregeln |
| `Install-Path.ps1` | `bin\` in den PATH aufnehmen |
| `Install-Continue.ps1` | Continue installieren und Konfiguration kopieren |
| `Install-Font.ps1` | Schrift des Erscheinungsbilds (IBM Plex Mono) für den Benutzer installieren |
| `Install-Style.ps1` | Erscheinungsbild „Nachtschicht“ aus `config\style.json` auf Windows Terminal und Claude Code anwenden (`-Remove` nimmt es zurück) |
| `claude-local.ps1` | Starter hinter dem Befehl `claude-local` |

## Lizenz

MIT, siehe [LICENSE](LICENSE). Die Chat-Vorlagen in `config\templates\` sind angepasste
Fassungen der Vorlagen aus den Modelldateien und stehen unter der Lizenz des jeweiligen
Modells.

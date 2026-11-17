# Architektur

## Ziel

Ein Coding-Agent, der sich wie Claude Code bedient, aber vollständig lokal läuft: ohne
Token-Limit, ohne Cloud und mit einem Modell, das Anfragen nicht ablehnt. Das Projekt soll
über lange Zeit pflegbar bleiben: Jede Einstellung hat genau einen Ort, jedes Skript genau
eine Aufgabe.

## Die Schichten

```
Terminal / VS Code
   │  claude-local                 bin\claude-local.cmd → scripts\claude-local.ps1
   ▼
Claude Code (CLI)                  Agent: liest und schreibt Dateien, führt Befehle aus
   │  Anthropic-kompatible API     http://127.0.0.1:8080/v1/messages
   ▼
llama-server (Router)              Backend: nimmt Anfragen an, startet je Modell einen Prozess
   │  ein Kindprozess je Modell
   ▼
Modellprofil, z. B. local-coder    Eintrag in config\models.json
   └─ GGUF-Datei                   E:\LlamaCpp\models\*.gguf
```

Continue (Chat und Autocomplete im Editor) spricht mit demselben Server über dessen
OpenAI-kompatible Schnittstelle.

Jede Schicht ist einzeln austauschbar:

| Schicht | Aktuell | Wo ändern | Beschreibung |
|---|---|---|---|
| Agent | Claude Code | `config\agent.json`, `scripts\claude-local.ps1` | [agent.md](agent.md) |
| Backend | llama.cpp (`llama-server`) | `config\server.json` | [backend.md](backend.md) |
| Modelle | Qwen 3.6 27B und 35B-A3B unzensiert, Qwen 3.8 27B unzensiert | `config\models.json` | [modelle.md](modelle.md) |

## Ordnerstruktur

```
bin\                 Befehle für den PATH (claude-local.cmd)
config\              alle Einstellungen
  server.json          llama-server: Installationsort, Version, Adresse
  models.json          Modellprofile: Datei, Kontext, GPU-Aufteilung, Sampling
  agent.json           Claude Code: Standardmodell, Kurznamen, Modellauswahl, Regeln
  entwicklungsregeln.md  Arbeitsregeln, die das lokale Modell in jeder Sitzung bekommt
  abschluss.md         Erinnerung der Abschlussprüfung (Test, README, Einstellungen)
  zweiter-blick.md     Prüfauftrag für den zweiten Blick (zweites Modell prüft den Diff)
  befehle\             Befehle /lokal:feature, /lokal:bugfix, /lokal:pruefen (Plugin für claude-local)
  projects.json        New-Project.ps1: Vorlagen, Sprachen, Zielordner
  templates\           Chat-Vorlagen (Jinja) für Modelle, deren eigene Vorlage nicht passt
  continue.config.yaml Konfiguration der VS-Code-Erweiterung Continue
  benchmark.json       welche Profile und Aufgaben der Benchmark misst
  guard.json           Schutzregeln: was das lokale Modell nicht oder nur nach Rückfrage darf (sicherheit.md)
  style.json           Erscheinungsbild: Farben, Zeichen, Texte (stil.md)
scripts\             ein Skript je Aufgabe (Einrichten, Starten, Testen, Messen)
  style\               Shell.ps1 (Eingabezeile, Begrüßung), Statusline.ps1 (Statuszeile von Claude Code)
  lib\                 gemeinsame Bausteine: Config.ps1, Server.ps1, Measure.ps1, Session.ps1, Safety.ps1, Quality.ps1, Review.ps1, Tasks.ps1, Projects.ps1
  hooks\               Guard-Tool.ps1: Wächter, den Claude Code vor jedem Werkzeug-Aufruf startet;
                       Check-Stop.ps1: Abschlussprüfung, bevor das Modell eine Antwort beendet
  _common.ps1          bindet lib\ ein; jedes Skript beginnt damit
benchmark\tasks\     Aufgaben für den Agenten-Benchmark (Vorlage, Auftrag, Prüfung, Musterlösung)
benchmark\lib\       rulecheck.py: misst in den Prüfungen, ob die Arbeitsregeln eingehalten wurden
benchmark\overlays\  Zusätze, die eine Aufgabe wie ein Projekt aus der Vorlage ausstatten
templates\projekt\   Vorlagen für neue Projekte (gemeinsam\, python\, powershell\), siehe projekte.md
tests\               Prüffälle für die Skripte (guard-cases.json für Test-Guard.ps1)
docs\                Dokumentation
logs\                Messergebnisse (results.jsonl, model-tests.log)
```

Außerhalb des Repositorys, weil groß oder erzeugt (Ort: `installRoot` in `config\server.json`):

```
E:\LlamaCpp\
  b12433\            Programme einer llama.cpp-Version (ein Ordner je Version)
  models\            GGUF-Dateien
  run\models.ini     aus config\models.json erzeugte Modellliste für den Server
  run\sessions\      Markierungen der laufenden Sitzungen von claude-local
  run\stop\          Stand der Abschlussprüfung je Sitzung
  run\api-key.txt    Schlüssel des Servers (geheim, wird beim ersten Start erzeugt)
  logs\server.log    Protokoll des Servers
  logs\guard.log     was der Wächter gesperrt oder zur Rückfrage gestellt hat
  downloads\         geladene Archive
```

## Grundsätze

- **Konfiguration steht in `config\`, nicht in Skripten.** Skripte lesen alle Werte über
  `scripts\lib\Config.ps1`. Wer etwas ändern will, ändert eine Datei in `config\` und
  startet den Server neu.
- **Eine Quelle je Angabe.** Adresse und Port stehen nur in `server.json`, Modelle nur in
  `models.json`. Ausnahme: `continue.config.yaml` wiederholt Adresse und Modellnamen, weil
  Continue die anderen Dateien nicht lesen kann; `Install-Continue.ps1` prüft die Namen.
- **Skripte sind wiederholbar.** Jedes Skript kann beliebig oft laufen und stellt den
  Soll-Zustand her.
- **Ein Skript, eine Aufgabe.** Gemeinsame Logik steht in `scripts\lib\`, nie doppelt.
- **Das normale Claude Code bleibt unberührt.** `claude-local` setzt seine Variablen nur
  für den eigenen Prozess. `claude` und die VS-Code-Extension nutzen weiter das
  Anthropic-Konto.
- **Jede Änderung wird dokumentiert.** Was gemacht und gemessen wurde, steht in
  [protokoll.md](protokoll.md); die betroffene Beschreibung wird im selben Schritt angepasst.

## Warum diese Entscheidungen

**Warum llama.cpp direkt statt Ollama (seit 2026-11-14):** Ollama startet intern ebenfalls
`llama-server`, legt aber eine eigene Schicht darüber. Direkt angesprochen lassen sich die
Optionen je Modell setzen (vor allem die GPU-Aufteilung, die bei Ollama für alle Modelle
gleich sein musste), und es gibt keine zweite Stelle mit eigenen Einstellungen mehr (die
Ollama-App überstimmte Umgebungsvariablen). Messwerte: [modellwahl.md](modellwahl.md).

**Warum der Router-Modus:** Ein einzelner `llama-server` bedient genau ein Modell. Im
Router-Modus wählt die Anfrage das Modell über den Namen, der Server lädt es bei Bedarf und
entlädt andere, wenn der Speicher nicht reicht. So funktionieren der Wechsel mit `/model`
und das kleine Autocomplete-Modell neben dem großen ohne eigenes Zutun.

**Warum "unzensiert" am Modell hängt:** Ob eine Anfrage abgelehnt wird, entscheidet das
Modell. Der Agent reicht nur Text und Tool-Aufrufe durch. Deshalb genügt es, das Modell zu
tauschen.

**Warum Claude Code als Agent:** Die Bedienung ist identisch zu dem, was schon genutzt
wird, und `llama-server` unterstützt die Anthropic-API direkt.

**Warum `models.json` statt der INI-Datei des Servers:** `llama-server` liest seine
Modellliste aus einer INI-Datei mit absoluten Pfaden. Die Skripte brauchen dieselben
Angaben (Kontextgröße für Claude Code, Dateipfad für den Benchmark). Deshalb ist die
JSON-Datei die Quelle, und `scripts\lib\Server.ps1` erzeugt die INI-Datei bei jedem Start.

# Architektur

## Ziel

Ein Coding-Agent, der sich wie Claude Code bedient, aber vollständig lokal läuft: ohne
Token-Limit, ohne Cloud und mit einem Modell, das Anfragen nicht ablehnt. Das Projekt soll
über lange Zeit pflegbar bleiben: Jede Einstellung hat genau einen Ort, jedes Skript genau
eine Aufgabe.

## Die Schichten

```
Terminal / VS Code
   │  unzensiert                   bin\unzensiert.cmd → scripts\unzensiert.ps1
   ▼
Unzensiert (eigener Agent)         liest und schreibt Dateien, führt Befehle aus (scripts\lib\Agent*.ps1)
   │  OpenAI-kompatible API        http://127.0.0.1:8080/v1/chat/completions
   ▼
llama-server (Router)              Backend: nimmt Anfragen an, startet je Modell einen Prozess
   │  ein Kindprozess je Modell
   ▼
Modellprofil, z. B. local-coder    Eintrag in config\models.json (+ config\machine.json)
   └─ GGUF-Datei                   <installRoot>\models\*.gguf
```

Zum Vergleich gibt es den zweiten Weg zum selben Server: `claude-local`
(`bin\claude-local.cmd` → `scripts\claude-local.ps1`) startet Claude Code, das über die
Anthropic-kompatible Schnittstelle `/v1/messages` spricht. Wächter, Abschlussprüfung,
Arbeitsregeln, Befehle und Modellauswahl teilen sich beide Agenten.

Darunter liegt die Einrichtung: `Install.cmd` bzw. der Einzeiler `install.ps1` startet
`scripts\Install.ps1`, der den Rechner erkennt (`lib\Machine.ps1`), llama.cpp und das
passende Modell lädt (`lib\Download.ps1`) und die Werte des Rechners in
`config\machine.json` schreibt ([einrichtung.md](einrichtung.md)).

Continue (Chat und Autocomplete im Editor) spricht mit demselben Server über dessen
OpenAI-kompatible Schnittstelle.

Jede Schicht ist einzeln austauschbar:

| Schicht | Aktuell | Wo ändern | Beschreibung |
|---|---|---|---|
| Agent | Unzensiert; zum Vergleich Claude Code über `claude-local` | `config\unzensiert.json`, `config\agent.json`, `scripts\unzensiert.ps1`, `scripts\claude-local.ps1` | [unzensiert.md](unzensiert.md), [agent.md](agent.md) |
| Backend | llama.cpp (`llama-server`) | `config\server.json` | [backend.md](backend.md) |
| Modelle | Qwen 3.6 27B und 35B-A3B unzensiert, Qwen 3.8 27B unzensiert | `config\models.json` | [modelle.md](modelle.md) |

## Ordnerstruktur

```
Install.cmd          Installieren oder reparieren per Doppelklick (startet scripts\Install.ps1)
Uninstall.cmd        wieder entfernen (scripts\Uninstall.ps1)
install.ps1          Einzeiler-Installation: holt das neueste Release (sonst main), startet scripts\Install.ps1
VERSION              Version des Programms; Releases auf GitHub tragen den Tag vX.Y.Z
bin\                 Befehle für den PATH (unzensiert.cmd, claude-local.cmd)
config\              alle Einstellungen
  server.json          llama-server: Version, Pakete je Grafikkarte, Adresse, Grenzen
  models.json          Modellprofile: Datei, Download, Kontext, Sampling
  setups.json          Hardware-Stufen: welches Modell der Installer für wie viel Grafikspeicher vorschlägt
  planner.json         Planer: Reserven, Kontextgrößen, Toleranz (planer.md)
  machine.json         Werte dieses Rechners (Ordner, berechnete Verteilung, Standardmodell, Kalibrierung); vom Installer, nicht im Repository
  agent.json           beide Agenten: Standardmodell, Kurznamen, Modellauswahl, Regeln, Abschlussprüfung, Werkzeuge
  unzensiert.json      Unzensiert: Rechte, Kontext, Zeitgrenzen, Befehle ohne Rückfrage (unzensiert.md)
  unzensiert-prompt.md Systemprompt von Unzensiert
  updates.json         automatische Updates aus den Releases auf GitHub
  entwicklungsregeln.md  Arbeitsregeln, die das lokale Modell in jeder Sitzung bekommt
  abschluss.md         Erinnerung der Abschlussprüfung (Test, README, Einstellungen)
  zweiter-blick.md     Prüfauftrag für den zweiten Blick (zweites Modell prüft den Diff)
  befehle\             Befehle /lokal:feature, /lokal:bugfix, /lokal:pruefen (Plugin für claude-local)
  projects.json        New-Project.ps1: Vorlagen, Sprachen, Zielordner
  templates\           Chat-Vorlagen (Jinja) für Modelle, deren eigene Vorlage nicht passt
  continue.config.yaml Konfiguration der VS-Code-Erweiterung Continue
  benchmark.json       welche Profile und Aufgaben der Benchmark misst
  guard.json           Schutzregeln: was das lokale Modell nicht oder nur nach Rückfrage darf (sicherheit.md)
  style.json           welches Erscheinungsbild gilt (stil.md)
  styles\              je Stil Farben, Zeichen, Texte, Schrift für Bilder aus Zeichen: ausbruch.json, nachtschicht.json
scripts\             ein Skript je Aufgabe (Einrichten, Starten, Testen, Messen)
  style\               Shell.ps1 (Eingabezeile, Begrüßung), Statusline.ps1 (Statuszeile von Claude Code)
  lib\                 gemeinsame Bausteine: Config.ps1, Machine.ps1, Download.ps1, Planner.ps1, Dialog.ps1, Server.ps1,
                       Measure.ps1, Session.ps1, Safety.ps1, Quality.ps1, Review.ps1, Tasks.ps1, Projects.ps1,
                       Style.ps1, CharArt.ps1, Update.ps1; der Agent Unzensiert in AgentApi.ps1, AgentTools.ps1,
                       AgentPrompt.ps1, AgentSession.ps1, AgentUi.ps1, AgentLoop.ps1, AgentRepl.ps1
  hooks\               GuardRules.ps1: Regeln des Wächters, die Unzensiert im eigenen Prozess prüft;
                       Guard-Tool.ps1: Wächter, den Claude Code vor jedem Werkzeug-Aufruf startet;
                       Check-Stop.ps1: Abschlussprüfung, bevor das Modell eine Antwort beendet;
                       HookEnvironment.ps1: Installations- und Projektordner für beide
  _common.ps1          bindet lib\ ein; jedes Skript beginnt damit
benchmark\tasks\     Aufgaben für den Agenten-Benchmark (Vorlage, Auftrag, Prüfung, Musterlösung)
benchmark\lib\       rulecheck.py: misst in den Prüfungen, ob die Arbeitsregeln eingehalten wurden
benchmark\overlays\  Zusätze, die eine Aufgabe wie ein Projekt aus der Vorlage ausstatten
templates\projekt\   Vorlagen für neue Projekte (gemeinsam\, python\, powershell\), siehe projekte.md
tests\               Prüffälle für die Skripte (guard-cases.json für Test-Guard.ps1)
docs\                Dokumentation
logs\                Messergebnisse (results.jsonl, model-tests.log)
```

Außerhalb des Repositorys, weil groß oder erzeugt. Der Ort ist `installRoot`: Der
Installer schlägt `claude-local` auf dem Laufwerk mit dem meisten Platz vor und merkt ihn in
`config\machine.json`; ohne diese Datei gilt `%LOCALAPPDATA%\claude-local` aus
`config\server.json`. Auf dem Entwicklungsrechner ist es `E:\LlamaCpp`.

```
<installRoot>\
  b12433\            Programme einer llama.cpp-Version (ein Ordner je Version, package.txt nennt das Paket)
  models\            GGUF-Dateien
  run\models.ini     aus config\models.json erzeugte Modellliste für den Server
  run\sessions\      Markierungen der laufenden Sitzungen (unzensiert und claude-local)
  run\update-check.json  wann zuletzt nach einem Release gesehen wurde
  sessions\          gespeicherte Unterhaltungen von Unzensiert, ein Ordner je Projektordner
  unzensiert-history.txt  frühere Eingaben in Unzensiert
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
- **Projekt und Rechner getrennt.** Die Dateien in `config\` gelten auf jedem Rechner.
  Was nur für einen Rechner stimmt (Ordner, Aufteilung auf bestimmte Karten,
  Standardmodell), steht in `config\machine.json`, nicht im Repository. Keine festen
  Laufwerke, Kartennamen oder Kartenaufteilungen in den gemeinsamen Dateien;
  `Test-Install.ps1` prüft das für die Modellprofile.
- **Eine Quelle je Angabe.** Adresse und Port stehen nur in `server.json`, Modelle nur in
  `models.json`. Ausnahme: `continue.config.yaml` wiederholt Adresse und Modellnamen, weil
  Continue die anderen Dateien nicht lesen kann; `Install-Continue.ps1` prüft die Namen.
- **Skripte sind wiederholbar.** Jedes Skript kann beliebig oft laufen und stellt den
  Soll-Zustand her.
- **Ein Skript, eine Aufgabe.** Gemeinsame Logik steht in `scripts\lib\`, nie doppelt.
- **Das normale Claude Code bleibt unberührt.** `claude-local` setzt seine Variablen nur
  für den eigenen Prozess. `claude` und die VS-Code-Extension nutzen weiter das
  Anthropic-Konto. Unzensiert braucht Claude Code gar nicht.
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

**Warum ein eigener Agent (seit 2026-11-17):** Claude Code ist ein Programm von Anthropic,
das für die Cloud gebaut ist: sein Systemprompt mit Werkzeugen hat am lokalen Server etwa
26.000 Tokens, jeder Hook ist ein eigener Prozess, und jede neue Version kann das Verhalten
mit lokalen Modellen ändern. Unzensiert ist auf lokale Modelle zugeschnitten (erste Anfrage
2.808 Tokens, Wächter im eigenen Prozess, Hilfen gegen Schleifen) und gehört zum Projekt;
Bedienung, Werkzeuge und Erscheinungsbild folgen Claude Code, damit sich nichts umlernen
muss. Es ist in PowerShell 5.1 geschrieben, weil das auf jedem Windows vorhanden ist und das
übrige Projekt schon darin steht. `claude-local` bleibt, damit der Benchmark beide
vergleichen kann ([unzensiert.md](unzensiert.md)).

**Warum zuerst Claude Code als Agent:** Die Bedienung war identisch zu dem, was schon
genutzt wurde, und `llama-server` unterstützt die Anthropic-API direkt.

**Warum `models.json` statt der INI-Datei des Servers:** `llama-server` liest seine
Modellliste aus einer INI-Datei mit absoluten Pfaden. Die Skripte brauchen dieselben
Angaben (Kontextgröße für Claude Code, Dateipfad für den Benchmark). Deshalb ist die
JSON-Datei die Quelle, und `scripts\lib\Server.ps1` erzeugt die INI-Datei bei jedem Start.

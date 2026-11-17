# Projekte mit dem lokalen Modell

Wie ein Projekt angelegt und bearbeitet wird, damit es pflegbar bleibt, auch wenn ein
lokales Modell den größten Teil des Codes schreibt. Messwerte dazu:
[modellwahl.md](modellwahl.md).

## Neues Projekt anlegen

```
powershell -ExecutionPolicy Bypass -File scripts\New-Project.ps1 -Name mein-tool
powershell -ExecutionPolicy Bypass -File scripts\New-Project.ps1 -Name mein-tool -Language powershell -Purpose "Räumt Protokolldateien auf."
```

| Parameter | Bedeutung |
|---|---|
| `-Name` | Name des Projekts und des Ordners |
| `-Language` | `python` (Standard) oder `powershell` |
| `-Path` | übergeordneter Ordner, Standard `projectsRoot`: `%USERPROFILE%\Projects` aus `config\projects.json`, auf diesem Rechner ggf. aus `config\machine.json` (Entwicklungsrechner: `E:\Projekte`) |
| `-Purpose` | ein bis zwei Sätze für README und Architektur |
| `-NoGit` | kein Repository, kein erster Commit |

Ein vorhandener Ordner wird nie angefasst. Das neue Projekt besteht sofort seinen eigenen
Prüfbefehl und hat einen ersten Commit. Gibt es keine globale Git-Identität, übernimmt das
neue Repository Name und Adresse aus diesem Repository.

Danach: Zweck in die README schreiben, im Projektordner `claude-local` starten.

## Was die Vorlage enthält

| Datei oder Ordner | Zweck |
|---|---|
| `README.md` | Zweck, Voraussetzungen, Start, Prüfen, Aufbau, Einstellungen |
| `CLAUDE.md` | kurze Hinweise für das Modell: Befehle und wo was hingehört, mit Verweisen auf Musterdateien |
| `config\settings.json` | Einstellungen des Programms; ein Baustein liest sie (`config.py` oder `scripts\lib\Config.ps1`) |
| `config\check.json` | Schritte des Prüfbefehls |
| `scripts\Check.ps1` | der eine Prüfbefehl: Syntax, Tests, Linter (falls installiert) |
| `.githooks\pre-commit` | führt den Prüfbefehl vor jedem Commit aus |
| `tests\` | ein erster Test als Muster |
| `docs\architektur.md` | Module und ihre öffentlichen Schnittstellen |
| `docs\entscheidungen\` | je Entscheidung eine Datei `NNNN-titel.md` (Lage, Entscheidung, Gründe, Verworfenes), Muster `0000-vorlage.md` |
| `facts\facts.json` | Quelle der Wahrheit für Fakten von außen (Pins, Spannungen, fremde Schnittstellen), jeder mit Quelle; Abschnitt „Fakten“ unten |
| `facts\boards\esp32.json` | Platinenprofil ESP32: vorhandene Pins, nur Eingang, Flash, Strapping |
| `scripts\check_facts.py` | Schritt „Fakten“ des Prüfbefehls |
| `CHANGELOG.md` | Änderungen je Version, Schema Haupt.Neben.Fehler |
| `.gitignore` | Python-Cache, Editor-Dateien, Geheimnisse |

Die Vorlagen liegen in `templates\projekt\`: `gemeinsam\` kommt in jedes Projekt, dazu der
Ordner der Sprache. Platzhalter: `{{NAME}}`, `{{PAKET}}`, `{{ZWECK}}`, `{{DATUM}}`; ein
Ordner `__PAKET__` bekommt den Paketnamen.

**Eine Sprache ergänzen:** Ordner in `templates\projekt\` anlegen, Namen unter `languages`
in `config\projects.json` eintragen, in `scripts\Test-Templates.ps1` einen eingebauten
Fehler für die Sprache ergänzen, dann `Test-Templates.ps1` ausführen.

## Der Prüfbefehl

```
powershell -ExecutionPolicy Bypass -File scripts\Check.ps1
```

Führt die Schritte aus `config\check.json` der Reihe nach aus und endet mit Exit-Code 1,
wenn einer scheitert.

| Feld eines Schritts | Bedeutung |
|---|---|
| `name` | Bezeichnung in der Ausgabe |
| `command` | Befehl, läuft im Projektordner; Exit-Code 0 heißt bestanden |
| `builtin` | statt `command`: `powershell-syntax` prüft, dass alle `.ps1`-Dateien lesbar und reines ASCII sind |
| `needs` | Programm, das der Schritt braucht |
| `optional` | fehlt das Programm aus `needs`, wird der Schritt übersprungen statt als Fehler gezählt |

Derselbe Befehl läuft an drei Stellen: von Hand, im Git-Hook vor jedem Commit und in der
Abschlussprüfung von `claude-local` ([agent.md](agent.md)), bevor das Modell eine Aufgabe
als erledigt meldet.

Die Linter-Schritte (`ruff`, `PSScriptAnalyzer`) sind als optional eingetragen. Beide
Programme sind auf diesem Rechner nicht installiert; die Schritte sind deshalb nicht
ausprobiert. Eine Suche nach Geheimnissen und eine Prüfung der Abhängigkeiten gehören zu
den Punkten S7 und N9 im [Zukunftsplan](roadmap.md) und fehlen noch.

**Ein vorhandenes Projekt nachrüsten:** `scripts\Check.ps1` aus
`templates\projekt\gemeinsam\scripts\` kopieren, `config\check.json` mit den Befehlen des
Projekts anlegen, eine kurze `CLAUDE.md` nach dem Muster der Vorlage schreiben. Genau das
tut die Benchmark-Variante `-Overlay projekt` ([erweitern.md](erweitern.md)).

## Fakten: eine Quelle der Wahrheit

Anlass: Bei echter Arbeit an einer ESP32-Firmware erfand `local-coder` Hardware-Fakten
(Pins, Spannungen, Konfigurationsschlüssel) und ließ nach Änderungen README, Schaltplan
und Code widersprüchlich zurück. Beides fängt der Benchmark nicht; eine Gegenprüfung mit
einem großen Modell fand es.

Jedes Projekt hat deshalb `facts\facts.json`: jeder Fakt von außen genau einmal, mit
Quelle oder als Annahme gekennzeichnet. `scripts\check_facts.py` läuft im Prüfbefehl
(also auch im Git-Hook und in der Abschlussprüfung) und meldet als Fehler:

| Prüfung | Beispiel der Meldung |
|---|---|
| Fakt ohne Quelle (außer `"status": "annahme"`, das nur gewarnt wird) | `fact 'uart0.tx' has no 'source'` |
| Name im Code mit anderem Wert (`#define`, Zuweisung in C, Python, PowerShell, Schlüssel in JSON/YAML/INI) | `main/ir/ir.h:21 sets IR_LED_PIN = 14, facts say GPIO15` |
| Pin in der Doku mit falschem Signal (`GPIO18 (SID`, `SID = GPIO18`) | `README.md:47 gives SID as GPIO18, facts say GPIO17` |
| Pin in Doku oder Code, der nicht in den Fakten steht | `GPIO31 is mentioned in README.md ... (and esp32 has no GPIO31)` |
| ein Pin zweimal vergeben (je Gerät) | `GPIO15 on device 'controller' is given to several facts` |
| gegen das Platinenprofil: Pin fehlt, Ausgang auf einem Eingangs-Pin, Flash-Pin | `GPIO39 is input-only on esp32 but is used as 'out'` |

Zahlen werden als Zahlen verglichen (`0x76` gleich `118`, `3.3` gleich `3.3V`), Pins in
jeder Schreibweise (`GPIO4`, `GPIO_NUM_4`, `4`). Strapping-Pins und Annahmen erscheinen als
Warnung. Aufbau der Datei: `facts\README.md` im Projekt.

Ausprobiert an einer Kopie des ESP32-Projekts `HackMD` mit 25 Fakten für zwei Geräte:
ohne Fehler bestanden, nachdem fünf in der Doku erwähnte freie Pins unter
`allow_unlisted_pins` standen; alle acht absichtlich eingebauten Fehler (falscher Pin in
README und Header, falsche Puffergröße in der zweiten Firmware, Flash-Pin, Ausgang auf
Eingangs-Pin, nicht vorhandener Pin, Fakt ohne Quelle, nicht erfasster Pin) gefunden.

Die Regel dazu steht in der `CLAUDE.md` der Vorlage und für alle Projekte in
`config\entwicklungsregeln.md` (Abschnitt „Fakten belegen statt raten“).

**Ein vorhandenes Projekt nachrüsten:** `facts\` und `scripts\check_facts.py` aus
`templates\projekt\gemeinsam\` kopieren, Fakten eintragen, den Schritt
`python -B scripts\check_facts.py` in den Prüfbefehl des Projekts aufnehmen.

## Arbeitsweise in einem Projekt

- **Feste Abläufe:** `/lokal:feature <Beschreibung>`, `/lokal:bugfix <Fehler>`,
  `/lokal:pruefen` ([agent.md](agent.md)).
- **Kleine Schritte:** ein Auftrag je Sitzung, danach `/clear`. Ein Commit je
  abgeschlossener Änderung. Große Vorhaben zuerst als Liste in `docs\` zerlegen, dann Punkt
  für Punkt beauftragen. Eine Aufgabe, die viele Dateien auf einmal braucht, gelingt
  auch mit 128k Kontext nicht jedes Mal (gemessen: Aufgabe `longcontext`, 3 von 6).
- **Schnittstellen:** Was andere Module benutzen dürfen, steht in der Tabelle in
  `docs\architektur.md`. Ändert sich eine Schnittstelle, ein Dateiformat oder eine
  Abhängigkeit, gehört eine Datei nach `docs\entscheidungen\` und ein Eintrag in
  `CHANGELOG.md`.

## Prüfen der Vorlagen

```
powershell -ExecutionPolicy Bypass -File scripts\Test-Templates.ps1
```

Legt je Sprache ein Projekt in einem temporären Ordner an und prüft: alle Platzhalter
gefüllt, Prüfbefehl besteht, erster Commit geht durch den Git-Hook, eingebaute Fehler
lassen den Prüfbefehl scheitern (eine Kopie, die `facts\facts.json` widerspricht, ein Fakt
ohne Quelle, ein scheiternder Test), der scheiternde Test auch den Commit.

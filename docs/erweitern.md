# Erweitern

Wo man ansetzt, um das Projekt zu verändern. Alle Befehle laufen aus dem Projektordner,
Skripte jeweils mit `powershell -ExecutionPolicy Bypass -File scripts\<Name>`.

## Wegweiser

| Vorhaben | Wo | Beschreibung |
|---|---|---|
| Neues Modell aufnehmen (mit `download`-Eintrag) | `config\models.json` | [modelle.md](modelle.md) |
| Verteilung auf Karten und Hauptspeicher neu berechnen | `scripts\Plan-Models.ps1 -Verify` | [planer.md](planer.md) |
| Reserven, Kontextgrößen oder Toleranz des Planers ändern | `config\planner.json` (je Rechner: `planner` in `machine.json`) | [planer.md](planer.md) |
| Kontext oder GPU-Aufteilung nur für diesen Rechner von Hand setzen | `config\machine.json` (der Planer überschreibt das beim nächsten Lauf) | [einrichtung.md](einrichtung.md) |
| Ändern, welches Modell der Installer für wie viel Grafikspeicher vorschlägt | `config\setups.json`, gemessen mit `Test-Model.ps1` | [einrichtung.md](einrichtung.md) |
| Installer ändern | `scripts\Install.ps1`, `lib\Machine.ps1`, `lib\Download.ps1`, danach `Test-Install.ps1` | [einrichtung.md](einrichtung.md) |
| Standardmodell, Kurznamen oder Auswahl von `/model` ändern | `config\agent.json` | [agent.md](agent.md) |
| Arbeitsregeln des lokalen Modells ändern | `config\entwicklungsregeln.md` | [agent.md](agent.md) |
| Abschlussprüfung ändern oder abschalten | `stopCheck` in `config\agent.json`, Text in `config\abschluss.md` | [agent.md](agent.md) |
| Zweiten Blick ändern (Prüfer, Schwelle) oder abschalten | `review` in `config\agent.json`, Prüfauftrag in `config\zweiter-blick.md` | [agent.md](agent.md) |
| Befehl für einen festen Ablauf ergänzen | Datei in `config\befehle\commands\` | [agent.md](agent.md) |
| Projektvorlage ändern, Sprache ergänzen | `templates\projekt\`, `config\projects.json` | [projekte.md](projekte.md) |
| llama.cpp aktualisieren, Port ändern | `config\server.json` | [backend.md](backend.md) |
| Schutzregeln ändern (was gesperrt ist, wobei gefragt wird) | `config\guard.json`, Fälle in `tests\guard-cases.json` | [sicherheit.md](sicherheit.md) |
| Modelle oder Einstellungen vergleichen | `config\benchmark.json` | unten |
| Anderen Agenten anbinden | neuer Starter | [agent.md](agent.md) |

## Modelle und Einstellungen vergleichen

`scripts\Benchmark-Models.ps1` misst jedes Profil aus `config\benchmark.json`: Ladezeit,
Tempo, MTP-Trefferquote, Tool-Calls, GPU-Speicher und die Agenten-Aufgaben, die ein Agent
löst und eine versteckte Prüfung bewertet. Die Prüfung hält außerdem fest, welche
Arbeitsregeln der Agent eingehalten hat.

- **Welcher Agent:** `agent` in `config\benchmark.json` (`unzensiert`), für einen Lauf
  `-Agent unzensiert` oder `-Agent claude-local`. Beide bekommen dieselben Argumente,
  dieselben erlaubten Befehle (`allowedTools`) und denselben Werkzeugsatz; jeder Agent hat
  seinen eigenen Datensatz (Feld `client`), Läufe unter demselben Label stehen im Bericht
  nebeneinander. Datensätze von vor 2026-11-17 zählen als `claude-local`.
Ergebnis: `docs\benchmark.md`, Rohdaten: `logs\benchmark\results.jsonl`.

- **Neues Modell aufnehmen:** Profil anlegen ([modelle.md](modelle.md)), Namen unter
  `models` in `config\benchmark.json` eintragen, Skript starten. Schon gemessene Profile
  werden übersprungen.
- **Eine Einstellung vergleichen** (Kontext, GPU-Aufteilung, Denkaufwand, MTP-Länge):
  entweder ein zweites Profil mit dem anderen Wert anlegen und beide messen, oder den Wert
  im Profil ändern, `Restart-Server.ps1` ausführen und mit `-Label <name>` messen. Das
  Label trennt die Läufe im Bericht.
- **Nur einen Teil messen:** `-Only "local-c*"` wählt Profile, `-Tasks planner` oder
  `-Tasks bugfix,feature` wählt Aufgaben. Nur Rohwerte ohne Agenten: `-SkipAgent`.
- **Wie ein Projekt aus der Vorlage:** `-Overlay projekt` legt über jede Aufgabe, was ein
  Projekt aus `New-Project.ps1` hat: eine kurze `CLAUDE.md`, `config\check.json` und den
  Prüfbefehl `scripts\Check.ps1` (Dateien in `benchmark\overlays\projekt\`, gemeinsame
  Dateien in `overlay.json`). So lässt sich messen, was Projektnotizen und Prüfbefehl
  bewirken. `Test-Tasks.ps1 -Overlay projekt` prüft, dass die Aufgaben damit stimmen.
- **Mit einem Befehl:** `-Prefix /lokal:feature` setzt den Text vor jeden Auftrag.
- **Mit zweitem Blick:** `-Git` macht jeden Arbeitsordner zu einem Git-Repository mit den
  Aufgabendateien als erstem Commit. Nur dann sieht die Abschlussprüfung einen Diff, und
  der zweite Blick ([agent.md](agent.md)) läuft mit. Ohne `-Git` misst der Benchmark
  alles außer dem zweiten Blick. `-ReviewModel local-coder` wählt für diesen Lauf einen
  anderen Prüfer (über die Umgebungsvariable `CLAUDE_LOCAL_REVIEW_MODEL`, die Claude Code
  an die Abschlussprüfung weitergibt), `-ExtraSeconds 300` verlängert jedes Zeitlimit um
  die Dauer der Prüfung. Jeder Lauf vermerkt im Ergebnis die Prüfungen aus
  `review.log` (Befund, Dauer).
- **Ruhezustand:** Während das Skript läuft, verhindert es den Ruhezustand des Rechners
  (`SetThreadExecutionState`, keine Systemeinstellung; die Anforderung endet mit dem
  Skript). Vorher ging der Rechner während langer Messungen schlafen.
- **Wenn der Agent nicht startet** (keine Ergebniszeile, etwa weil eine andere
  Sitzung gerade ein Skript oder `config\` umbaut), bricht das Skript mit Exit-Code 1 ab.
  Die Läufe davor bleiben im Datensatz, der Grund steht im Feld `error`. Die fehlenden
  Aufgaben dann mit `-Tasks` unter einem neuen `-Label` messen. Während einer Messung
  nichts an `config\` und `scripts\` ändern: jeder Lauf liest beides neu.
- **Zuverlässigkeit prüfen:** `-Repeat 3` löst jede Aufgabe dreimal. Ein einzelner Lauf ist
  wegen der Zufälligkeit der Modelle nur ein Anhaltspunkt; dieselbe Aufgabe dauerte mit
  demselben Modell schon zwischen 122 s und 412 s.
- **Während der Messung** VS Code mit Continue nicht benutzen: Das Autocomplete-Modell
  lädt sonst nach und verfälscht die Werte.

Alle neun Aufgaben dreimal dauern je Profil etwa anderthalb Stunden; die fünf schwereren
allein etwa eine Stunde.

Einstellungen in `config\benchmark.json`:

| Feld | Bedeutung |
|---|---|
| `tasks`, `models` | was gemessen wird |
| `agentTimeoutSeconds` | Zeitlimit je Lauf (600 s) |
| `taskTimeoutSeconds` | abweichendes Zeitlimit für einzelne Aufgaben |
| `allowedTools` | Befehle, die der Agent ohne Rückfrage ausführen darf (im Benchmark sitzt niemand am Terminal; alles andere gilt als abgelehnt) |
| `workDir` | Arbeitsordner, außerhalb des Repositorys |

### Vorhandene Aufgaben

| Aufgabe | Inhalt | Schwierigkeit | Geprüfte Regeln |
|---|---|---|---|
| `bugfix` | einen Fehler finden und beheben | leicht | keine |
| `feature` | eine Funktion ergänzen | leicht | keine |
| `multifile` | Änderung über mehrere Dateien | leicht | keine |
| `planner` | Raumplaner nach `SPEC.md`: Fehler in zwei Modulen beheben, ein Modul und einen Befehl der Kommandozeile ergänzen; die Prüfung testet Randfälle, die die mitgelieferten Tests nicht abdecken | mittel | keine |
| `extend` | bestehendes Projekt um mehrere Lager erweitern; alte Tests, alte Aufrufe und alte Datendateien müssen weiter funktionieren | mittel | 5 |
| `refactor` | Umbau über sieben Dateien: aller Dateizugriff in ein neues Modul, atomar schreiben; die Prüfung liest auch den Aufbau des Codes | mittel | 4 |
| `psscript` | PowerShell-Skript um Filter, JSON-Ausgabe und tolerantes Lesen erweitern; muss mit Windows PowerShell 5.1 laufen | schwer | 5 |
| `screenshot` | Fehler aus einem Bildschirmfoto beheben; was schiefgeht, steht nur im Bild | leicht bis mittel | 4 |
| `longcontext` | 15 Regeländerungen aus einer Liste auf 20 unterschiedlich geschriebene Ländermodule anwenden und ein Land ergänzen; füllt den Kontext von 64k | schwer | 4 |
| `datenblatt` | Treiber für den erfundenen Sensor HX-7 nach beiliegendem Datenblatt; der Vorgänger HX-5 liegt daneben und unterscheidet sich in Adresse, Byte-Reihenfolge, Formel und Ablauf. Misst Faktentreue: Wer vom HX-5 abschreibt oder rät, fällt durch | mittel | 5 |
| `pinwechsel` | Pumpe von GPIO17 auf GPIO23 verlegen, Regensensor auf GPIO17 ergänzen. Die Pins stehen an fünf Stellen (Konfiguration, Rückfallwert im Code, README, Verdrahtungsplan mit Pin der Stiftleiste, `facts.json`), dazu die Tests. Misst Konsistenz über Dateien; das Projekt hat Prüfbefehl und Faktenabgleich wie eines aus `New-Project.ps1` | mittel | 5 |

Die drei leichten Aufgaben bestehen alle guten Modelle; sie unterscheiden nur über die
Zeit. Die Bewertung der Ergebnisse steht in [modellwahl.md](modellwahl.md).

### Arbeitsregeln messen

Die Aufträge der fünf neueren Aufgaben verlangen nur das Ergebnis. Dass dabei die README
angepasst, ein Test geschrieben oder eine Einstellung in die Konfigurationsdatei gelegt
wird, verlangt allein `config\entwicklungsregeln.md`. Ob es geschieht, misst die Prüfung
mit den Bausteinen aus `benchmark\lib\rulecheck.py` und gibt es als Zeile
`RULES {"readme": true, ...}` aus. Bestanden oder nicht hängt davon nicht ab.

| Regel | Gilt als eingehalten, wenn |
|---|---|
| `readme` | die README geändert wurde und das Neue nennt |
| `tests` | eine neue oder geänderte Testdatei das Neue nennt |
| `config` | der neue Wert (Name des Standardlagers, Anzahl der Quellen) als neuer Eintrag in der Konfigurationsdatei steht |
| `docstrings` | jede neue öffentliche Funktion, Klasse und jedes neue Modul eine Beschreibung hat |
| `headers` | jedes neue PowerShell-Skript mit einem Kommentar beginnt |
| `nodeadcode` | keine neue Zeile auskommentierten Code enthält (in Python nur Kommentare, die sich als Python übersetzen lassen; Rechenbeispiele wie `# raw = 512 -> 2.0` zählen nicht) |
| `fakten` | `facts/facts.json` einen neuen Fakt zum Neuen hat, mit Quelle |

Das sind Näherungen, die sich mechanisch prüfen lassen. Sie sagen, ob etwas geschehen
ist, nicht wie gut. Der Bericht zeigt die Quote je Lauf, je Aufgabe und je Regel.

### Eine neue Aufgabe

Ordner `benchmark\tasks\<name>\` mit

- `files\`: Ausgangsdateien, werden in einen Arbeitsordner kopiert,
- `prompt.txt`: Auftrag an den Agenten,
- `check.py`: bekommt den Arbeitsordner als Argument, Exit-Code 0 heißt bestanden; optional
  gibt sie die Zeile `RULES {...}` aus (Muster: `benchmark\tasks\extend\check.py`),
- `solution\`: Musterlösung, nur die Dateien, die sich gegenüber `files\` ändern. Der Agent
  bekommt sie nicht zu sehen.

Den Namen in `config\benchmark.json` unter `tasks` eintragen, dann
`scripts\Test-Tasks.ps1` ausführen: Die Prüfung muss auf der unveränderten Vorlage
durchfallen und auf der Musterlösung bestehen, mit allen Regeln eingehalten. Bringt eine
Aufgabe Werkzeuge der Projektvorlage mit (`scripts\check_facts.py`, `scripts\Check.ps1`,
wie `pinwechsel`), prüft `Test-Tasks.ps1` auch, dass es die aktuelle Fassung ist; nach
einer Änderung an der Vorlage die Kopie erneuern. Dieser
Selbsttest hat beim Bau der Aufgaben zwei Fehler in den Prüfungen gefunden, bevor ein
Modell lief, und einen dritten erst die Messung (Protokoll vom 2026-11-15).

Zwei Aufgaben haben erzeugte Dateien:

- `longcontext`: `python benchmark\tasks\longcontext\generate.py` schreibt `files\`,
  `solution\`, `probe.py` und `expected.json` aus einer Tabelle im Skript. Änderungen an
  der Aufgabe gehören in die Tabelle, nicht in die erzeugten Dateien.
- `screenshot`: `benchmark\tasks\screenshot\Make-Image.ps1` zeichnet `files\error.png`.

## Neue Skripte

- Ein Skript hat eine Aufgabe. Der Kopfkommentar sagt, was es tut und wie man es aufruft.
- Am Anfang `. "$PSScriptRoot\_common.ps1"`. Das bindet die Bausteine aus `scripts\lib\` ein:

  | Datei | Funktionen |
  |---|---|
  | `lib\Config.ps1` | `Get-ServerConfig`, `Get-AgentConfig`, `Get-ModelsConfig`, `Get-ModelNames`, `Get-ModelProfile`, `Get-ModelContextSize`, `Resolve-ModelName`, `Read-JsonFile` |
  | `lib\Server.ps1` | `Start-Server`, `Stop-Server`, `Test-ServerUp`, `Invoke-ServerApi`, `Get-ServerModels`, `Wait-ModelLoaded`, `Stop-AllModels` |
  | `lib\Measure.ps1` | `Measure-Generation`, `Measure-PromptSpeed`, `Test-ToolCall`, `Get-GpuMemory` |
  | `lib\Tasks.ps1` | `New-TaskWorkCopy`, `Invoke-TaskCheck`, `Get-TaskOverlayDir` |
  | `lib\Quality.ps1` | `Get-QualitySettings`, `Get-PluginDir`, `Merge-Settings`, `Invoke-StopHook` |
  | `lib\Review.ps1` | `Invoke-Review`, `Get-ChangeForReview`, `New-ReviewRequest`, `ConvertFrom-ReviewAnswer`, `Get-LastUserPrompt`, `Invoke-Git` |
  | `lib\Projects.ps1` | `Get-ProjectsConfig`, `New-ProjectFromTemplate`, `Invoke-ProjectCheck`, `Initialize-ProjectRepository` |

- Werte (Pfade, Ports, Modellnamen) kommen aus `config\`, nie aus dem Skript.
- Gemeinsam nutzbare Logik gehört in `scripts\lib\`, in die Datei mit dem passenden Thema.
  Ein neues Thema bekommt eine neue Datei, die in `_common.ps1` eingebunden wird.
- Nur ASCII-Zeichen in `.ps1`-Dateien. Windows PowerShell 5.1 liest Dateien ohne BOM als
  ANSI und zerstört Umlaute.
- Skripte müssen wiederholbar sein: Ein zweiter Lauf ändert nichts mehr.

## Dokumentation pflegen

- Jede Änderung bekommt einen Eintrag oben in [protokoll.md](protokoll.md): was gemacht
  wurde, was gemessen wurde, was offen ist.
- Die Beschreibung der betroffenen Schicht (`backend.md`, `modelle.md`, `agent.md`) und
  die Tabellen in der `README.md` werden im selben Schritt angepasst.
- `docs\benchmark.md` wird erzeugt und nicht von Hand bearbeitet. Die Bewertung der Zahlen
  steht in [modellwahl.md](modellwahl.md).

## Ein Cloud-Modell als Ausweichlösung

`claude-local` nimmt die Adresse aus `config\server.json`. Für einen Dienst mit
Anthropic-kompatibler API und Schlüssel legt man einen eigenen Starter nach dem Muster von
`scripts\claude-local.ps1` an, der `ANTHROPIC_AUTH_TOKEN` aus einer Umgebungsvariable
setzt. Schlüssel gehören nicht in die Dateien dieses Ordners.

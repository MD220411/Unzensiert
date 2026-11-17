# Agent: Claude Code über `claude-local`

Der Standard-Agent des Projekts ist seit 2026-11-17 **Unzensiert** (`unzensiert`, eigenes
Programm, [unzensiert.md](unzensiert.md)). `claude-local` bleibt als Vergleich: Es startet
das normale Claude Code, verbindet es aber mit dem lokalen Server statt mit der
Anthropic-Cloud. Der Starter ist `scripts\claude-local.ps1`; `bin\claude-local.cmd` macht
ihn in jedem Terminal verfügbar.

Beide Agenten teilen sich `config\agent.json` (Modell, Kurznamen, Auswahl, Arbeitsregeln,
Abschlussprüfung, zweiter Blick, Befehle, Werkzeuge, `onExit`), den Wächter und das
Erscheinungsbild. Was in diesem Dokument zu diesen Teilen steht, gilt also auch für
Unzensiert; nur das Starten, die Variablen von Claude Code und die Grenzen am Ende betreffen
allein `claude-local`.

## Benutzen

| Befehl | Wirkung |
|---|---|
| `claude-local` | Sitzung mit dem Standardmodell (`model` in `config\agent.json`, auf diesem Rechner ggf. aus `config\machine.json`). Ist es nicht geladen, startet das erste geladene Modell aus `picker`. |
| `claude-local -Model schnell` | Sitzung mit einem Kurznamen aus `aliases` oder einem Profilnamen aus `config\models.json`. Ist das Modell nicht geladen, nennt `claude-local` den Befehl zum Laden. |
| `/model` in der Sitzung | Modell wechseln, ohne die Sitzung zu beenden. Zur Auswahl stehen die Einträge unter `picker`, deren Modell auf diesem Rechner geladen ist. |
| `claude-local -p "Frage"` | einmalige Antwort ohne Sitzung |
| `claude-local --continue` | letzte Sitzung im Ordner fortsetzen |
| `claude-local -OnExit keep` | Modelle nach dieser Sitzung geladen lassen (überschreibt `onExit`) |

Alle weiteren Argumente gehen unverändert an Claude Code.

## Einstellungen (`config\agent.json`)

| Schlüssel | Wert | Zweck |
|---|---|---|
| `model` | `local-coder` | Standardmodell. Der Installer schreibt das Modell, das zum Grafikspeicher passt, nach `machine.json` ([einrichtung.md](einrichtung.md)). |
| `aliases` | `unzensiert` → `local-coder`, `schnell` → `local-fast`, `qwen38` → `local-qwen38` | Kurznamen für `-Model` |
| `picker` | Liste aus `model`, `label`, `description` | Einträge der Auswahl von `/model` |
| `rulesFile` | `entwicklungsregeln.md` | Datei in `config\`, die an den Systemprompt angehängt wird. Leer lassen oder entfernen, um ohne Regeln zu starten. |
| `stopCheck` | `enabled`, `commands`, `timeoutSeconds`, `maxBlocks`, `reminderFile` | Abschlussprüfung, siehe unten. `enabled: false` schaltet sie ab. |
| `pluginDir` | `befehle` | Ordner in `config\` mit den Befehlen `/lokal:feature`, `/lokal:bugfix`, `/lokal:pruefen`. Leer lassen oder entfernen, um ohne sie zu starten. |
| `tools` | `Bash,Read,Edit,Write,Glob,Grep` | Werkzeuge, die das Modell benutzen darf (bei Claude Code `--tools`). Leer lassen oder entfernen für den vollen Satz von Claude Code; Unzensiert kennt nur `Bash`, `PowerShell`, `Read`, `Edit`, `Write`, `Glob`, `Grep`. Ohne Git for Windows ersetzen beide `Bash` durch `PowerShell`, siehe „Schlanker Werkzeugsatz“. |
| `env` | Auto-Memory und mitgelieferte Skills aus | Schalter von Claude Code, nur für diesen Prozess gesetzt |
| `onExit` | `unload` | Was geschieht, wenn die letzte Sitzung endet: `unload` entlädt die Modelle des Agenten, `stop` beendet den Server, `keep` lässt alles geladen. Siehe unten. |
| `gitCheck` | `true` | Hinweis beim Start, wenn der Ordner kein Git-Repository ist oder nicht gesicherte Änderungen hat ([sicherheit.md](sicherheit.md)) |
| `contextSafetyFactor` | `0.9` | Claude Code bekommt 90 % von `ctx-size` als Fenster gemeldet, weil es die Tokenzahl nur schätzt |
| `fallbackContextTokens` | `32768` | Annahme für Profile ohne `ctx-size` |
| `maxOutputTokens` | `16384` | Obergrenze für eine Antwort |

Die Adresse des Servers steht nicht hier, sondern in `config\server.json`.

## Arbeitsregeln für das lokale Modell

`config\entwicklungsregeln.md` wird in jeder Sitzung an den Systemprompt von Claude Code
angehängt (`--append-system-prompt-file`). Die Regeln richten das Modell darauf aus,
Software so zu bauen, dass sie pflegbar bleibt: erst Struktur, dann Code; ein Modul je
Aufgabe; Einstellungen in Konfigurationsdateien; README, Dateikopf und Docstrings; Tests
vor dem Abschluss; Dokumentation im selben Schritt wie die Änderung.

- **Regeln ändern:** die Datei bearbeiten. Gilt ab der nächsten Sitzung, kein Neustart des
  Servers nötig.
- **Kurz halten.** Die Datei zählt in jeder Anfrage zum Kontext (vor dem Abschnitt zu PowerShell gemessen 544 Tokens, jetzt geschätzt 750).
- **Vorrang:** Eine `CLAUDE.md` im jeweiligen Projektordner und ausdrückliche Anweisungen
  in der Sitzung gehen vor. Projektspezifisches (Sprache, Aufbau, Befehle zum Testen) gehört
  in die `CLAUDE.md` des Projekts, nicht in die allgemeinen Regeln.

Der Abschnitt „PowerShell-Skripte“ der Regeln nennt die Eigenheiten von Windows
PowerShell 5.1, an denen die Modelle im Benchmark scheiterten (stderr und Exit-Code,
ungewollte Ausgabe, Listen mit einem Eintrag).

Der Abschnitt „Fakten belegen statt raten“ antwortet auf zwei Fehlerklassen aus echter
Arbeit an einer ESP32-Firmware: erfundene Fakten (Pins, Spannungen,
Konfigurationsschlüssel) und Werte, die nach einer Änderung in README, Schaltplan und Code
auseinanderliefen. Im Projekt prüft das ein Programm ([projekte.md](projekte.md),
Abschnitt „Fakten“); ob die Regel allein etwas bewirkt, ist nicht gemessen.

Ein lokales 27B-Modell hält sich an solche Regeln weniger zuverlässig als Claude:
gemessen entstanden README-Eintrag und Test ohne Nachfrage in weniger als der Hälfte der
Läufe. Deshalb fragt die Abschlussprüfung am Ende jeder Antwort mit Änderungen noch einmal danach.

## Abschlussprüfung

Will das Modell eine Antwort beenden, in der es Dateien geändert hat, läuft
`scripts\hooks\Check-Stop.ps1` (ein `Stop`-Hook von Claude Code):

1. **Prüfbefehl des Projekts.** Gibt es im Projektordner `scripts\Check.ps1` oder
   `Check.ps1` (`commands`), wird er ausgeführt. Scheitert er, bekommt das Modell das Ende
   der Ausgabe zurück und arbeitet weiter, höchstens `maxBlocks`-mal (3) hintereinander.
   Danach darf es aufhören, und im Terminal erscheint ein Hinweis, selbst nachzusehen.
2. **Erinnerung.** Einmal je Antwort bekommt das Modell den Text aus
   `config\abschluss.md`: Test geschrieben und ausgeführt, README angepasst, feste Werte
   in der Konfigurationsdatei, aufgeräumt. Fehlt etwas, holt es das nach. Ein Punkt
   entfällt, wenn die in dieser Antwort geänderten Dateien zeigen, dass er erledigt ist
   (`reminderPoints`: eine Testdatei, eine README oder Datei in `docs`, eine
   Konfigurationsdatei). Ist kein Punkt offen, kommt keine Erinnerung.

Nach Antworten ohne Dateiänderung geschieht nichts. Ob Dateien geändert wurden, liest der
Hook aus dem Verlauf der Sitzung (Aufrufe von `Edit` und `Write`); Änderungen, die nur über
Shell-Befehle entstehen, sieht er nicht. Er zählt nur echte Aufrufe (`tool_use`-Blöcke, jede
Aufruf-ID einmal): Claude Code schreibt auch die Werkzeug-Beschreibungen in den Verlauf und
wiederholt frühere Nachrichten bei jeder Anfrage. Ein Fehler im Hook selbst lässt das Modell immer
aufhören. Der Stand je Sitzung liegt in `<installRoot>\run\stop\`; den Ordner bekommt der
Hook über die Variable `CLAUDE_LOCAL_ROOT` (`scripts\hooks\HookEnvironment.ps1`).

Gemessen an 15 Läufen von `local-coder` ([modellwahl.md](modellwahl.md)): Mit der
Abschlussprüfung nennt die README das Neue in 15 statt 7 Läufen, ein Test steht in 15
statt 6. Der Preis ist Zeit: Mit der ersten Fassung, die immer erinnerte, dauerten die
Läufe zusammen 50 % länger, weil jede Antwort
mit Änderungen mindestens eine weitere Runde des Modells braucht. Den Wert in die
Konfigurationsdatei bringt die Erinnerung allein nicht (0 von 6); das leistet die
`CLAUDE.md` des Projekts (5 von 6).

- **Text ändern:** `config\abschluss.md` bearbeiten. Punkte haben die Form
  `- [name] Text`; welche Dateien einen Punkt erledigen, steht unter `reminderPoints` in
  `config\agent.json` (`doneWhenEdited`: Muster für den Pfad; `codeOnly`: Punkt zählt
  nur, wenn Programmcode geändert wurde).
- **Immer den ganzen Text:** `reminderPoints` entfernen.
- **Nur den Prüfbefehl, keine Erinnerung:** `reminderFile` auf `""` setzen.
- **Abschalten:** `enabled` auf `false`.
- **Fehlersuche:** Umgebungsvariable `CLAUDE_LOCAL_HOOK_DEBUG=1` setzen; der Hook
  schreibt dann nach stderr, warum er aufgegeben hat.

Einen Prüfbefehl bekommt jedes Projekt aus `New-Project.ps1` mit; ein vorhandenes Projekt
lässt sich nachrüsten ([projekte.md](projekte.md)).

## Zweiter Blick

Nach einer größeren Änderung prüft ein zweites lokales Modell in frischem Kontext, ob sie
stimmt. Es ist der dritte Schritt der Abschlussprüfung und läuft einmal je Antwort, sobald
Prüfbefehl und Erinnerung nichts mehr offen haben, und nur in einem Git-Repository:

1. `scripts\Invoke-Review.ps1` sammelt die nicht committete Änderung (Diff gegen `HEAD`
   und neue Dateien) und zählt die geänderten Zeilen. Unter `minChangedLines` (20) endet
   es hier.
2. Der Prüfer (`local-qwen38`; ist er auf diesem Rechner nicht geladen, das Standardmodell
   selbst in frischem Kontext) bekommt in einer einzigen Anfrage: den Prüfauftrag
   `config\zweiter-blick.md`, die letzte Eingabe des Nutzers als Auftrag, die
   `CLAUDE.md` und `facts\facts.json` des Projekts, den Diff und die geänderten Dateien
   vollständig, die kleinsten zuerst, soweit sie in `maxFileChars` passen. Ganze Dateien
   braucht er, weil ein Widerspruch oft in einer unveränderten Zeile steht, etwa wenn die
   README weiter unten noch den alten Pin nennt. Er hat keine Werkzeuge und führt nichts
   aus.
3. Er antwortet mit Zeilen `FEHLER | datei:zeile | ...` und `HINWEIS | ...` oder mit
   `KEINE BEFUNDE`.
4. Bei mindestens einem `FEHLER` bekommt der Autor die Liste zurück, mit dem Auftrag,
   jeden Befund am Code nachzuprüfen, Zutreffendes zu beheben und Unzutreffendes dem
   Nutzer zu begründen. Nur `HINWEIS`-Zeilen sieht der Nutzer im Terminal, der Autor
   arbeitet nicht weiter. Läuft der Prüfer nicht, weil Server, Modell oder Zeit fehlen,
   erscheint ein Hinweis, und das Modell darf aufhören.

Der Router lädt den Prüfer und entlädt dafür `local-coder`. Danach lädt er `local-coder`
wieder und liest die Unterhaltung neu ein. Jeder Lauf steht als JSON-Zeile in
`<installRoot>\logs\review.log` (Projekt, Zeilen, Sekunden, Anzahl Fehler und Hinweise).

Von Hand, auch für ein anderes Modell als Prüfer:

```
powershell -ExecutionPolicy Bypass -File scripts\Invoke-Review.ps1 -Folder E:\Projekte\mein-tool -Task "was die Änderung leisten soll"
powershell -ExecutionPolicy Bypass -File scripts\Invoke-Review.ps1 -Folder E:\Projekte\mein-tool -Model local-coder
```

| Schlüssel unter `review` | Wert | Zweck |
|---|---|---|
| `enabled` | `true` | zweiter Blick an oder aus |
| `model` | `local-qwen38` | Profil oder Alias des Prüfers |
| `minChangedLines` | 20 | kleinere Änderungen prüft er nicht (Annahme: darunter lohnen sich Wartezeit und Neuladen nicht) |
| `maxDiffChars`, `maxFileChars` | 60000, 80000 | Obergrenzen für Diff und ganze Dateien in der Anfrage |
| `maxTokens` | 8192 | Obergrenze der Antwort einschließlich Denken |
| `timeoutSeconds` | 600 | einschließlich Laden des Prüfers; das Zeitlimit des Hooks wächst um diesen Wert |
| `instructionsFile` | `zweiter-blick.md` | Prüfauftrag in `config\` |

**Gemessen** an einer Kopie des ESP32-Projekts `HackMD`, an einer Änderung mit 20 Zeilen:
IR-LED auf einen anderen Pin verlegt und `ir_send_repeat` ergänzt, mit eingebauten
Fehlern. Je Lauf eine Anfrage:

| Eingebauter Fehler | `local-qwen38` (3 Läufe) | `local-coder` als Prüfer (2 Läufe) |
|---|---|---|
| Schleife sendet einmal zu oft (`i <= count`) | 3 / 3 | 2 / 2 |
| README nennt weiter unten noch den alten Pin | 3 / 3 | 2 / 2 |
| Kopfkommentare in `ir.h` und `ir.c` nennen den alten Pin | 3 / 3 | 2 / 2 |
| `vTaskDelay(gap_ms)`: Millisekunden statt Ticks | 0 / 3 | 2 / 2 (einmal als Hinweis) |
| erfundene Angabe „GPIO26 ist 5V-tolerant“ | 0 / 3 | 1 / 2 (als Hinweis) |
| Dauer, mit Laden | 33 bis 87 s | 76 bis 128 s |

Dieselbe Änderung ohne Fehler: kein Befund in je zwei Läufen beider Prüfer, also kein
Fehlalarm. Von Ende zu Ende über die Abschlussprüfung, so aufgerufen wie Claude Code es
tut: Erinnerung, dann zweiter Blick (53 s), Befund an den Autor, danach Ende. Grenzen:
ein einziger Fall, wenige Läufe. Hier fand `local-coder` als Prüfer mehr, `local-qwen38`
war schneller. Der Nutzer hat `local-qwen38` gewählt (Variante A).

**Im Benchmark** (Lauf `h3-qwen38`, bisher nur `extend`, `refactor`, `psscript`, je
dreimal, Einzelheiten im [Protokoll](protokoll.md)): 9 Prüfungen, im Mittel 126 s. Ein
FEHLER-Befund, und der war echt (ein Test ohne `test_`, der nie lief); kein Fehlalarm;
ein durchgefallener Lauf blieb unbemerkt. Die drei Aufgaben dauerten zusammen 53 % länger
als ohne zweiten Blick. Die Messung mit `local-coder` als Prüfer und an den Aufgaben aus H4
steht noch aus ([Zukunftsplan](roadmap.md)).

- **Anderer Prüfer:** `model` ändern, etwa auf `local-coder`. Für einen einzelnen Lauf
  geht es auch über die Umgebungsvariable `CLAUDE_LOCAL_REVIEW_MODEL`; das nutzt
  `Benchmark-Models.ps1 -ReviewModel`.
- **Abschalten:** `enabled` auf `false`.

## Feste Abläufe als Befehle

| Befehl | Ablauf |
|---|---|
| `/lokal:feature <was gebaut werden soll>` | lesen, Abnahmekriterien, Plan, Tests, Code, prüfen, Dokumentation, Bericht |
| `/lokal:bugfix <Fehler, Meldung oder Bilddatei>` | nachstellen, Ursache, erst ein Test, der den Fehler zeigt, dann die Korrektur, prüfen, Bericht |
| `/lokal:pruefen [was]` | die letzten Änderungen mit frischem Blick prüfen, ohne etwas zu ändern; am besten in einer neuen Sitzung |

Die Befehle liegen als Plugin in `config\befehle\` (`commands\*.md`, je Datei ein Befehl)
und werden mit `--plugin-dir` nur für `claude-local` geladen; das normale `claude` bekommt
sie nicht. Der Vorsatz `lokal:` ist der Name des Plugins. Geprüft ist der Aufruf mit
`claude-local -p "/lokal:bugfix ..."`; `/bugfix` ohne Vorsatz wird dort nicht erkannt.
Ob die interaktive Sitzung die Befehle beim Tippen von `/` vorschlägt, ist nicht geprüft.

Gemessen ist nur `/lokal:feature`, an einer Aufgabe: `extend` dreimal, 2 bestanden, alle
15 Regeln eingehalten, auch der Wert in der Konfigurationsdatei (ohne Befehl 0 von 3).

Ein neuer Befehl ist eine neue Datei in `config\befehle\commands\` mit `description` im
Kopf; `$ARGUMENTS` steht für den Text hinter dem Befehl.

## GPU-Speicher nach der Sitzung

Endet eine Sitzung (`exit`, `/exit`, Strg+D, auch ein Lauf mit `-p`), räumt `claude-local`
auf und meldet das Ergebnis in einer Zeile, zum Beispiel
`claude-local: models unloaded, GPU memory used now (MiB): RTX 5070 Ti 7, RTX 3060 0`.

- **`unload` (Standard):** Das Startmodell und die Modelle aus `picker` werden entladen.
  Der Server läuft weiter und belegt keinen GPU-Speicher; Continue kann ihn weiter nutzen,
  das Autocomplete-Modell bleibt geladen.
- **`stop`:** Der Server wird beendet, damit auch das Autocomplete-Modell.
- **`keep`:** Nichts geschieht. Sinnvoll, wenn viele kurze Läufe aufeinander folgen; der
  Benchmark ruft `claude-local` deshalb mit `-OnExit keep` auf.

Läuft noch eine andere Sitzung von `claude-local`, bleiben die Modelle geladen, und erst
die letzte räumt auf. Jede Sitzung legt dafür eine Markierung in
`<installRoot>\run\sessions\` ab (`scripts\lib\Session.ps1`); Markierungen beendeter
Prozesse werden ignoriert und gelöscht.

Wird das Terminalfenster geschlossen, kann `claude-local` nicht aufräumen. Dann gibt das
Modell seinen Speicher nach 30 Minuten ohne Anfrage selbst frei
(`sleep-idle-seconds`, [backend.md](backend.md)).

## Schutz

Vor jedem Werkzeug-Aufruf des Modells läuft ein Wächter, der zerstörerische Befehle sperrt
und bei heiklen nachfragt; normale Arbeit im Projektordner bleibt frei. Sagt das Modell, ein
Befehl sei vom „Schutz von claude-local“ gesperrt, steht der Grund in der Meldung und in
`<installRoot>\logs\guard.log`. Regeln, Grenzen und wie man sie ändert:
[sicherheit.md](sicherheit.md).

## Bilder

Die Modelle des Agenten lesen Bilder: einfügen mit Alt+V, eine Datei ins Terminal ziehen
oder den Pfad nennen („sieh dir `fehler.png` an“). Voraussetzungen und Messwerte:
[modelle.md](modelle.md), Abschnitt „Bilder“.

## Schlanker Werkzeugsatz

Claude Code bringt viele Werkzeuge mit (Subagenten, Skills, Notizen, Web, Aufgabenlisten).
Jedes steht mit seiner Beschreibung im Prompt. Für ein lokales Modell ist das Ballast: Der
Prompt wird länger, und schwächere Modelle rufen die Extras ohne Anlass auf. `claude-local`
gibt deshalb nur die sechs Werkzeuge frei, die zum Programmieren nötig sind, und schaltet
Auto-Memory und die mitgelieferten Skills ab.

Gemessen mit `local-coder`, neun Läufe: 375 s mit dem schlanken Satz, 431 s mit dem vollen,
beide 9 von 9. Der Abstand liegt im Bereich der üblichen Streuung.

Wer Subagenten, Websuche oder Skills braucht, ergänzt die Namen in `tools`
(zum Beispiel `Agent`, `WebFetch`, `WebSearch`, `Skill`) oder entfernt den Schlüssel.

**Ohne Git for Windows.** Das Werkzeug `Bash` braucht Git Bash. Findet `claude-local` es
nicht (`lib\Machine.ps1`, `Find-GitBash`), ersetzt es `Bash` durch `PowerShell` und setzt
`CLAUDE_CODE_USE_POWERSHELL_TOOL=1`. Gemessen sind Benchmark und Arbeitsregeln nur mit
`Bash`; mit `PowerShell` ist der Agent ungetestet. Der Installer bietet Git for Windows an.

## Was `claude-local` setzt

Nur für den eigenen Prozess, das normale `claude` bleibt unverändert:

| Variable oder Argument | Zweck |
|---|---|
| `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY=` | Verbindung zum lokalen Server. Das Token ist der Schlüssel des Servers ([sicherheit.md](sicherheit.md)); ist keiner verlangt, steht dort `local`, weil Claude Code einen Wert braucht. |
| dieselbe Datei mit `hooks` | Wächter: prüft jeden Werkzeug-Aufruf des Modells, bevor er läuft ([sicherheit.md](sicherheit.md)). |
| `ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_OPUS/SONNET/HAIKU_MODEL` | Alle eingebauten Modellnamen zeigen auf das Startmodell, auch das kleine Modell für Hintergrundanfragen. |
| `CLAUDE_CODE_SUBAGENT_MODEL` (entfernt) | Subagenten bekommen kein festes Modell und folgen so dem Hauptmodell nach einem Wechsel mit `/model`. |
| `--settings <Datei>` mit `modelPicker` | Die Auswahl von `/model` zeigt die Einträge aus `picker` statt der Anthropic-Modelle. Die Datei (`%TEMP%\claude-local-settings.json`) gilt nur für diesen Start. |
| dieselbe Datei mit `theme` und `statusLine`, dazu `CLAUDE_LOCAL_LOOK=<Stimmung>` | Aussehen der lokalen Sitzung: Farbthema der lokalen Stimmung des aktiven Stils („Frei“ bei Ausbruch, „Glut“ bei Nachtschicht) und Statuszeile mit dem Speicher beider Grafikkarten. Nur wenn das Erscheinungsbild installiert ist ([stil.md](stil.md)). |
| `CLAUDE_CODE_MAX_CONTEXT_TOKENS` | Echtes Kontextfenster. Ohne den Wert nimmt Claude Code ein viel größeres Fenster an und komprimiert nie rechtzeitig. Der Wert gilt für die ganze Sitzung; bei mehreren Modellen in der Auswahl zählt das kleinste Fenster. |
| `CLAUDE_CODE_MAX_OUTPUT_TOKENS` | Antwortlänge begrenzen |
| `--append-system-prompt-file <Datei>` | Arbeitsregeln, siehe oben |
| `--settings <Datei>` mit `hooks.Stop` | Abschlussprüfung, siehe oben |
| `--plugin-dir <Ordner>` | Befehle `/lokal:feature`, `/lokal:bugfix`, `/lokal:pruefen`, siehe oben |
| `--tools <Liste>` | Schlanker Werkzeugsatz aus `tools`, siehe oben; ohne Git Bash mit `PowerShell` statt `Bash` und `CLAUDE_CODE_USE_POWERSHELL_TOOL=1` |
| `CLAUDE_LOCAL_ROOT`, `CLAUDE_LOCAL_PROJECTS` | Installations- und Projektordner dieses Rechners für die Hooks (Wächter, Abschlussprüfung), gesetzt von `scripts\_common.ps1` |
| `CLAUDE_CODE_DISABLE_AUTO_MEMORY`, `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS` | Aus `env`: keine Notizen ins Memory-Verzeichnis, keine mitgelieferten Skills |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | Keine Telemetrie und Update-Prüfungen im lokalen Modus |

## Bekannte Grenzen

- **Hintergrundanfragen nach einem Modellwechsel.** Das kleine Modell für Nebenaufgaben
  bleibt das Startmodell. Schickt Claude Code nach einem Wechsel mit `/model` solche
  Anfragen, lädt der Server das Startmodell wieder und entlädt das gewählte. In Läufen mit
  `-p` kamen keine vor; für interaktive Sitzungen ist es nicht gemessen.
- **Die Auswahl von `/model`** ist nur über den Start mit `-p` und die erzeugte
  Einstellungsdatei geprüft, nicht in einer interaktiven Sitzung.
- **Warnung `claude.ai connectors are disabled`** und die Zeile
  `[claude-code:unrecognized_model]` sind im lokalen Modus erwartet und ohne Auswirkung.
- **Kontext.** Auch 128k werden voll, Claude Code komprimiert dann. Für eine neue Aufgabe
  besser eine neue Sitzung oder `/clear`.

## Einen anderen Agenten anbinden

Jedes Werkzeug, das eine OpenAI-kompatible Adresse annimmt (Roo Code, Cline, OpenCode),
kann `http://127.0.0.1:8080/v1` mit einem Profilnamen als Modell benutzen. Einen eigenen
Starter legt man nach dem Muster von `scripts\claude-local.ps1` und `bin\claude-local.cmd` an.

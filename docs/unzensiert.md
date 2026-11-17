# Unzensiert: der eigene Agent

`unzensiert` ist der Coding-Agent dieses Projekts. Er arbeitet im aktuellen Ordner mit
einem lokalen Modell von `llama-server`: liest und ändert Dateien, führt Befehle aus und
prüft seine Arbeit. Er braucht kein weiteres Programm und keine Cloud. Er spricht die
OpenAI-kompatible Schnittstelle des Servers an (`/v1/chat/completions`, gestreamt, mit
Werkzeugen) und ist ganz in PowerShell 5.1 geschrieben, das auf jedem Windows vorhanden ist.

Bedienung, Werkzeuge, Arbeitsregeln, Wächter, Abschlussprüfung, zweiter Blick, die Befehle
`/feature`, `/bugfix`, `/pruefen` und das Erscheinungsbild sind dieselben wie bei
`claude-local`. `claude-local` (Claude Code am lokalen Server, [agent.md](agent.md)) bleibt
zum Vergleich erhalten; der Benchmark kann beide messen.

## Gemessen gegen Claude Code

Fünf Benchmark-Aufgaben mit `local-coder`, beide Agenten unter gleichen Bedingungen, je ein
Lauf (Lauf `vergleich1`, Bewertung in [modellwahl.md](modellwahl.md)):

| Aufgabe | Unzensiert | claude-local (Claude Code) |
|---|---|---|
| `screenshot` | 80 s, 16 Runden | 98 s, 22 Runden |
| `pinwechsel` | 80 s, 17 Runden | 123 s, 30 Runden |
| `datenblatt` | 105 s, 15 Runden | 124 s, 25 Runden |
| `extend` | 214 s, 21 Runden | 244 s, 34 Runden |
| `refactor` | 180 s, 19 Runden | 240 s, 48 Runden |
| **zusammen** | **5 / 5 bestanden, 659 s, 88 Runden, 42.640 Tokens, Regeln 22 / 23** | 5 / 5 bestanden, 829 s, 159 Runden, 48.858 Tokens, Regeln 21 / 23 |

Unzensiert war bei allen fünf Aufgaben schneller (zusammen 20 % weniger Zeit) und brauchte
45 % weniger Runden. Ein Lauf je Aufgabe liegt in der Streuung früherer Wiederholungen;
der Lauf mit `-Repeat 3` und den übrigen Aufgaben steht aus.

## Benutzen

| Befehl | Wirkung |
|---|---|
| `unzensiert` | Unterhaltung im Terminal mit dem Standardmodell (`model` in `config\agent.json`) |
| `unzensiert "Aufgabe"` | dasselbe, beginnt gleich mit dieser Anfrage |
| `unzensiert -Model schnell` | anderes Modell: Kurzname aus `aliases` oder Profilname |
| `unzensiert -p "Frage"` | eine Anfrage ohne Terminal, die Antwort als Text; die Anfrage kann auch über eine Pipe kommen |
| `unzensiert -p --output-format json ...` | dasselbe als eine JSON-Zeile (siehe unten) |
| `unzensiert -c` | die letzte Unterhaltung in diesem Ordner fortsetzen |
| `unzensiert --resume` | eine frühere Unterhaltung auswählen (`--resume <id>` direkt) |
| `unzensiert --permission-mode edits` | Rechte-Modus `ask`, `edits` oder `all` (die Namen von Claude Code gehen auch) |
| `unzensiert --allowedTools "Bash(python:*)"` | diese Aufrufe ohne Rückfrage erlauben, Schreibweise wie bei Claude Code |
| `unzensiert --max-turns 30` | höchstens so viele Runden mit Werkzeugaufrufen |
| `unzensiert -OnExit keep` | Modelle nach dem Ende geladen lassen (`unload`, `stop`, `keep`) |
| `unzensiert --version`, `--help` | Version, Hilfe |
| `unzensiert --update` | jetzt nach einem neuen Release sehen und es einspielen |
| `unzensiert --updates on` / `off` | automatische Updates auf diesem Rechner ein- oder ausschalten |

Der Server startet bei Bedarf mit, das Modell lädt bei der ersten Anfrage. Endet die letzte
Sitzung, werden die Modelle wie bei `claude-local` entladen (`onExit` in `config\agent.json`).

## In der Unterhaltung

| Taste oder Eingabe | Wirkung |
|---|---|
| Enter | senden |
| Shift+Enter (oder Strg+Enter) | neue Zeile |
| Pfeil hoch/runter | frühere Eingaben (gespeichert in `<installRoot>\unzensiert-history.txt`) |
| Esc oder Strg+C, während das Modell arbeitet | anhalten; ein laufender Befehl wird mit allen Unterprozessen beendet |
| Shift+Tab | Rechte-Modus wechseln (`ask` → `edits` → `all`); ein angefangener Text landet in der Liste früherer Eingaben |
| Alt+V | Bild aus der Zwischenablage einfügen; das Modell sieht es |
| `!befehl` | einen Befehl selbst ausführen; das Modell sieht Befehl und Ausgabe mit der nächsten Nachricht |
| `/help` | alle Befehle |
| `/model [Name oder Nummer]` | Modell wechseln (Einträge von `picker` in `config\agent.json`) |
| `/mode [ask, edits, all]` | Rechte-Modus setzen oder weiterschalten |
| `/compact [worauf achten]` | Unterhaltung jetzt zusammenfassen |
| `/clear` | neue Unterhaltung |
| `/resume [Nummer]` | frühere Unterhaltung dieses Ordners fortsetzen |
| `/status` | Modell, Kontext, Tokens, Rechte, Projektanweisungen, Datei der Unterhaltung |
| `/think` | Denken des Modells mitlesen oder nur die Länge zeigen |
| `/init` | das Modell schreibt eine `AGENTS.md` für das Projekt |
| `/feature`, `/bugfix`, `/pruefen` (auch `/lokal:feature` usw.) | feste Abläufe aus `config\befehle\commands\` ([agent.md](agent.md)) |
| `/exit` | beenden |

Vor jeder Eingabe steht eine Statuszeile: Stimmung und Modell, wie voll der Kontext ist, das
Tempo der letzten Antwort, der Rechte-Modus, der Speicher der Grafikkarten, Ordner und
Git-Stand. Die Farben kommen aus dem aktiven Stil (`config\style.json`, [stil.md](stil.md)),
im Stil „Ausbruch“ also die Stimmung „Frei“ wie bei `claude-local`.

Während das Modell denkt, zählt eine Zeile mit, wie viel es denkt; die Antwort erscheint
Wort für Wort, mit etwas Markdown (Überschriften, Listen, `Code`, Codeblöcke). Werkzeuge
erscheinen mit ihrem Ergebnis, Änderungen mit den entfernten und hinzugefügten Zeilen.

## Rechte

Zuerst entscheidet in jedem Modus der Wächter (`config\guard.json`, [sicherheit.md](sicherheit.md)):
Gesperrtes läuft nie, Heikles fragt immer. Danach gilt der Modus:

| Modus | Lesen (Read, Glob, Grep, Befehle, die nur lesen) | Dateien im Projektordner ändern (Edit, Write, Dateibefehle) | andere Befehle |
|---|---|---|---|
| `ask` (Standard) | ohne Frage | Frage | Frage |
| `edits` | ohne Frage | ohne Frage | Frage |
| `all` | ohne Frage | ohne Frage | ohne Frage |

- **Befehle, die nur lesen** (`readOnlyCommands`, `readOnlyGit` in `config\unzensiert.json`:
  `ls`, `cat`, `grep`, `git status`, `git diff`, `Get-ChildItem` ...) laufen auch als Teil
  einer längeren Zeile (`cd src && ls`). Eine Umleitung in eine Datei (`>`) oder eine
  Befehlsersetzung (`$(...)`) macht daraus wieder eine Frage.
- **Außerhalb des Projektordners** fragen Edit und Write auch in `edits`; nur `all` lässt
  sie ohne Frage zu.
- **Dateibefehle** (`fileCommands`: `mkdir`, `rm`, `mv`, `cp`, `New-Item`, `Remove-Item` ...)
  zählen in `edits` als Dateiänderung, wenn jedes Ziel im Projektordner liegt. Ein Ziel
  außerhalb, in einer Variablen oder der Projektordner selbst führt zur Frage.
- **Die Frage** zeigt den Befehl, bei Edit die Änderung (rot/grün), bei Write den Inhalt:
  `y` oder `j` ja, `a` oder `i` immer (für diese Sitzung: bei Befehlen das Programm, etwa
  `Bash(python:*)`, bei Dateien alle Änderungen), `n` oder Esc nein. Nach einem Nein wartet das Modell auf deine Anweisung.
- **Ohne Terminal** (`-p`) wird aus jeder Frage eine Ablehnung mit Begründung für das
  Modell. Nach drei Ablehnungen in einer Anfrage bekommt es den Hinweis, nicht weiter nach
  Umwegen zu suchen; nach neun endet die Anfrage.
- Befehlszeilen werden an `&&`, `||`, `;`, `|` und Zeilenumbrüchen außerhalb von
  Anführungszeichen geteilt; jedes Teilstück muss erlaubt sein, `python -c "a; b"` bleibt
  ein Befehl.

## Werkzeuge

Das Modell bekommt die Werkzeuge aus `tools` in `config\agent.json`, denselben schlanken
Satz wie Claude Code unter `claude-local` (`Bash,Read,Edit,Write,Glob,Grep`; ohne Git Bash
`PowerShell` statt `Bash`). Namen und Parameter sind die von Claude Code, so prüft derselbe
Wächter beide Agenten.

| Werkzeug | Was es tut |
|---|---|
| `Bash` | Befehl in Git Bash, `PowerShell` in Windows PowerShell 5.1; immer im Projektordner. Der Befehl kommt in eine Skriptdatei (kein Ärger mit Anführungszeichen), läuft ohne Eingabe, höchstens `commandTimeoutSeconds` (bis `commandMaxSeconds`, wenn das Modell mehr verlangt) und wird mit allen Unterprozessen beendet. Lange Ausgaben behalten Anfang und Ende, denn dort steht meist der Fehler. Python schreibt dabei UTF-8 (`PYTHONIOENCODING`). |
| `Read` | Datei mit Zeilennummern, Teile mit `offset`/`limit`; Bilder sieht das Modell als Bild |
| `Edit` | Text ersetzen; nur nach `Read` und nur, wenn die Datei seitdem nicht geändert wurde. Der Text muss genau einmal vorkommen (oder `replace_all`). Zeilenenden (CR LF), Kodierung und Byte-Order-Mark der Datei bleiben, wie sie waren. Findet es den Text nicht, sagt es, ob nur Einrückung oder Zeilenumbrüche abweichen. |
| `Write` | neue Datei, oder eine gelesene ganz ersetzen |
| `Glob` | Dateien nach Muster (`**/*.py`, `src/*.{ts,tsx}`), neueste zuerst, ohne `.git`, `node_modules`, `__pycache__`, `.venv` |
| `Grep` | Inhalt nach regulärem Ausdruck (.NET), Ausgabe `Pfad:Zeile:Text`, mit `glob`, `ignore_case`, `files_only` |

## Abschlussprüfung und zweiter Blick

Will das Modell eine Antwort beenden, in der es Dateien geändert hat, läuft dieselbe
Abschlussprüfung wie bei `claude-local` (`scripts\hooks\Check-Stop.ps1`, `stopCheck` und
`review` in `config\agent.json`, [agent.md](agent.md)): Prüfbefehl des Projekts, Erinnerung
an Test, README und Einstellungen, nach größeren Änderungen der zweite Blick. Unzensiert
schreibt dafür eine kurze Mitschrift im Format, das der Hook von Claude Code kennt
(Anfragen und Dateiänderungen, `<Sitzung>.hook.jsonl`). Meldet die Prüfung etwas, macht das
Modell weiter; die Meldungen nennen den Agenten (`CLAUDE_LOCAL_AGENT=Unzensiert`). Esc
bricht auch eine lange Prüfung ab.

## Kontext

Das Fenster ist `ctx-size` des Modellprofils. Unzensiert kennt nach jeder Antwort die
genaue Tokenzahl vom Server und schätzt nur das, was seitdem dazukam. Füllt die Unterhaltung
`compactAt` (80 %) des Fensters, kürzt es zuerst alte Werkzeugergebnisse (älter als
`keepRecentRounds` Runden) auf `oldToolResultChars` Zeichen; reicht das nicht, fasst das
Modell die Unterhaltung zusammen und arbeitet danach weiter, mit der letzten Anfrage im
Wortlaut. Passt eine Anfrage trotzdem nicht, fasst es zusammen und versucht es noch einmal.
Das Denken früherer Anfragen fällt weg (die Chat-Vorlagen lassen es ohnehin weg), das Denken
der laufenden Anfrage geht an das Modell zurück, so kann der Server seinen Cache
weiterverwenden: in einem Testlauf mit drei Anfragen kamen 8.629 von 8.719 Tokens aus dem
Cache.

## Gespeicherte Unterhaltungen

Jede Unterhaltung steht in `<installRoot>\sessions\<Projektordner>\<Start>.jsonl`, eine
Nachricht je Zeile; Bilder werden nicht gespeichert, nur ein Vermerk. Nach einer
Zusammenfassung steht dort eine Marke, ein Fortsetzen (`-c`, `--resume`, `/resume`) beginnt
dahinter und bekommt einen frischen Systemprompt (Datum, Git-Stand, Regeln von heute).

## Systemprompt

`config\unzensiert-prompt.md` mit den Fakten der Sitzung (Datum, Windows, Ordner, Git,
Shells), dazu die Anweisungen des Projekts (`projectFiles`: `AGENTS.md`, sonst `CLAUDE.md`,
aus dem Projektordner und allen Ordnern darüber, der nächste zuletzt) und die Arbeitsregeln
aus `rulesFile` in `config\agent.json`. Systemprompt und Werkzeugbeschreibungen haben
zusammen etwa 8.900 Zeichen; die erste Anfrage einer Aufgabe hatte gemessen 2.808 Tokens.
Claude Code schickt am lokalen Server zuerst etwa 26.000 Tokens ([README](../README.md)).

## Einmal-Lauf und JSON

`unzensiert -p` liest die Anfrage aus den Argumenten und, wenn etwas über eine Pipe oder
Datei kommt, aus der Standardeingabe (UTF-8). Mit `--output-format json` steht am Ende eine
Zeile im Format von Claude Code, die der Benchmark liest:

```json
{"type":"result","subtype":"success","is_error":false,"result":"...","num_turns":8,
 "duration_ms":24000,"session_id":"...","stop_reason":"done","agent":"unzensiert","version":"1.0.0",
 "usage":{"input_tokens":341,"output_tokens":326,"cache_read_input_tokens":11938},
 "modelUsage":{"local-coder":{"inputTokens":341,"outputTokens":326,"cacheReadInputTokens":11938,"costUSD":0}},
 "changed_files":["..."]}
```

`num_turns` zählt die Anfragen an das Modell, `stop_reason` ist `done`, `stopped`, `loop`
(dieselben Aufrufe immer wieder), `limit` (`--max-turns`) oder `error`. Hinweise wie
„Server startet“ gehen in einem Einmal-Lauf auf die Fehlerausgabe, die Standardausgabe
enthält nur das Ergebnis.

## Eingebaute Hilfen gegen Schleifen

- **Wiederholung:** Macht das Modell denselben Aufruf mit demselben Ergebnis zum dritten
  Mal, ohne dass sich dazwischen eine Datei geändert hat, steht ein Hinweis im Ergebnis; beim
  sechsten Mal endet die Anfrage (`maxRepeats`).
- **Abgelehnte Aufrufe:** siehe Rechte.
- **Abgeschnittene Aufrufe:** Endet eine Antwort an der Token-Grenze mitten in einem
  Werkzeugaufruf, erfährt das Modell, dass es kleinere Stücke schreiben soll.
- **Höchstzahl:** `maxToolRounds` Runden je Anfrage (200), `--max-turns` für einen Lauf.

## Einstellungen (`config\unzensiert.json`)

| Schlüssel | Wert | Zweck |
|---|---|---|
| `promptFile` | `unzensiert-prompt.md` | Systemprompt in `config\` |
| `projectFiles` | `AGENTS.md`, `CLAUDE.md` | Anweisungsdateien des Projekts, je Ordner die erste vorhandene |
| `permissionMode` | `ask` | Rechte-Modus beim Start |
| `readOnlyCommands`, `readOnlyGit` | Liste | Befehle, die ohne Frage laufen |
| `fileCommands` | Liste | Befehle, die in `edits` als Dateiänderung zählen |
| `maxToolRounds` | `200` | Runden je Anfrage |
| `maxRepeats` | `3` | Schwelle für Wiederholungen und Ablehnungen |
| `compactAt`, `keepRecentRounds`, `oldToolResultChars` | `0.80`, `6`, `1500` | Kontext, siehe oben |
| `toolResultChars` | `30000` | längste Ausgabe eines Befehls |
| `readLines` | `2000` | Zeilen, die `Read` ohne `limit` liefert |
| `commandTimeoutSeconds`, `commandMaxSeconds` | `120`, `600` | Zeitgrenzen für Befehle |
| `maxOutputTokens` | `16384` | längste Antwort; nie mehr, als im Fenster Platz hat |
| `showThinking` | `false` | Denken mitlesen (in der Sitzung `/think`) |
| `historyFile` | `unzensiert-history.txt` | frühere Eingaben, im Installationsordner |

Modell, Kurznamen, Auswahl von `/model`, Arbeitsregeln, Abschlussprüfung, zweiter Blick,
Werkzeuge und `onExit` kommen wie bei `claude-local` aus `config\agent.json`. Ein Rechner
kann jeden Wert in `config\machine.json` unter `"unzensiert"` ändern.

## Automatische Updates

Neue Versionen erscheinen als Releases auf GitHub (Tag `vX.Y.Z`, die Datei `VERSION` im
Projekt nennt die eigene). `unzensiert` sieht beim Start im Terminal höchstens alle
`checkHours` Stunden (24) nach (`config\updates.json`, Zeitgrenze `timeoutSeconds`). Ist ein
neueres Release da, holt es die Programmdateien – mit git den Tag, sonst das ZIP des Tags,
das über den Ordner gelegt wird; `config\machine.json` bleibt dabei unberührt –, installiert
den llama.cpp-Build der neuen Version (`Install-LlamaCpp.ps1`), startet den Server neu, wenn
sich der Build geändert hat und keine andere Sitzung läuft, und startet sich selbst neu.

- **Ausschalten:** `unzensiert --updates off` (steht dann in `config\machine.json` unter
  `"updates"`), einschalten mit `--updates on`. Der Installer fragt einmal.
- **Von Hand:** `unzensiert --update` sieht sofort nach, auch wenn die automatischen Updates
  aus sind; die Installationszeile aus der README tut es ebenfalls.
- **Nie angefasst** wird ein Ordner, in dem Programmdateien von Hand geändert wurden, und ein
  vollständiger git-Klon, der nicht auf einem Release steht (ein Entwicklungsordner). Nur
  Kopien des Installers (flache Klone, ZIP) und Klone auf einem Release-Tag werden
  aktualisiert. Der Stand von `main` zwischen zwei Releases kommt nie automatisch.
- **Release veröffentlichen** (nur für die Pflege des Repositorys):
  `scripts\New-Release.ps1 -Version 1.1.0 -Notes "..."` prüft Arbeitsstand, Zweig und Tag,
  führt die Prüfskripte aus, schreibt `VERSION`, committet, setzt den Tag, pusht und legt
  das Release mit `gh` an; `-DryRun` zeigt nur, was geschähe.

## Aufbau

| Datei | Inhalt |
|---|---|
| `scripts\unzensiert.ps1`, `bin\unzensiert.cmd` | Starter: Argumente, Update, Modell, Server, Sitzung |
| `scripts\lib\AgentApi.ps1` | JSON (JavaScriptSerializer von .NET, viel schneller als `ConvertTo-Json`) und die gestreamte Anfrage |
| `scripts\lib\AgentTools.ps1` | die Werkzeuge |
| `scripts\lib\AgentPrompt.ps1` | Systemprompt mit Projektanweisungen |
| `scripts\lib\AgentSession.ps1` | Nachrichten, gespeicherte Unterhaltungen, Größe des Kontexts |
| `scripts\lib\AgentUi.ps1` | Terminal: Antwort, Werkzeuge, Fragen, Eingabe (PSReadLine), Statuszeile |
| `scripts\lib\AgentLoop.ps1` | eine Anfrage: Modell, Wächter, Rechte, Werkzeuge, Abschlussprüfung, Kontext |
| `scripts\lib\AgentRepl.ps1` | Unterhaltung, Befehle mit Schrägstrich, Einmal-Lauf, Argumente |
| `scripts\lib\Update.ps1` | automatische Updates |
| `scripts\hooks\GuardRules.ps1` | Regeln des Wächters, gemeinsam mit dem Hook für Claude Code; Unzensiert prüft im eigenen Prozess (2,7 ms je Aufruf statt 280 ms für einen Hook-Prozess, gemessen) |
| `scripts\Test-Agent.ps1` | Prüfungen ohne Modell (etwa 5 s), `-WithModel` mit einer kleinen Aufgabe |
| `scripts\New-Release.ps1` | ein Release veröffentlichen |

Bewusste Eigenheiten von PowerShell 5.1, die der Code beachtet: Listen kommen aus Funktionen
mit führendem Komma zurück (sonst wird eine Liste mit einem Element zu diesem Element),
Daten für den Server enthalten keine Werte von Cmdlets (`New-Object`, `Join-Path`,
`Get-Date` verpacken sie in ein PSObject, das der Serialisierer nicht kennt), und Kinder-
prozesse starten über `Start-ChildProcess` (`lib\Machine.ps1`), weil .NET sonst auf einer
UTF-8-Konsole ein Byte-Order-Mark in ihre Eingabe schreibt.

## Grenzen

- **Die Bedienung im Terminal** (Tasten, Eingabezeile, Fragen) prüfen die Testskripte nur
  bis zur Ausgabe; Tastendrücke kann kein Skript nachstellen. Gemessen sind Einmal-Läufe
  und der Benchmark.
- **Während das Modell arbeitet,** liest Unzensiert die Tastatur nach Esc ab; was man in
  dieser Zeit tippt, geht verloren.
- Keine Subagenten, keine Websuche, keine MCP-Server: der Werkzeugsatz ist der schlanke von
  `claude-local`.
- **Bilder** gehen nur an Modelle mit Bild-Encoder (`mmproj`); sonst ersetzt Unzensiert sie
  durch einen Vermerk und fragt erneut.
- **Ohne PSReadLine** (sehr alte Systeme) gibt es nur eine einfache Eingabezeile ohne
  Verlauf und ohne Shift+Enter.

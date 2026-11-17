# Zukunftsplan

Was als Nächstes kommt, damit der lokale Coder sicherer, zuverlässiger, sparsamer und
schneller wird und Software baut, die sich über Jahre pflegen und erweitern lässt.
Stand: 2026-11-16.

**So wird der Plan benutzt:** von oben nach unten abarbeiten. Jeder Punkt nennt, woran man
misst, ob er etwas gebracht hat. Ein erledigter Punkt wandert mit seinem Messwert ins
[Protokoll](protokoll.md) und wird hier gestrichen. Ein Punkt ohne messbare Wirkung wird
zurückgenommen.

**Wie belastbar eine Angabe ist:**

| Kennzeichen | Bedeutung |
|---|---|
| gemessen | auf diesem Rechner mit `Test-Model.ps1`, `Benchmark-Models.ps1` oder einem Lauf im Protokoll belegt |
| belegt | steht in der Dokumentation oder im Quelltext von Claude Code oder llama.cpp, hier nicht ausprobiert |
| Annahme | plausibel, aber ungeprüft; vor einer Entscheidung messen |

## Ausgangslage

| Bereich | Stand | Beleg |
|---|---|---|
| Tempo | `local-coder` 57 bis 65 Tokens/s, `local-fast` 130 bis 137, Einlesen etwa 1500 Tokens/s | gemessen, `logs\model-tests.log` |
| Zuverlässigkeit | `local-coder` besteht alle 24 Läufe der vier älteren Aufgaben und 14 von 15 der fünf neuen (die lange Aufgabe 2 von 3); `local-fast` 3 von 15 (vor Stufe 3) | gemessen, [modellwahl.md](modellwahl.md) |
| Kontext | 128k (alle drei Profile), davon rund 5200 Tokens für Systemprompt, Werkzeuge und Regeln, bevor die erste Frage gestellt ist | gemessen, Server-Protokoll |
| GPU-Speicher | `local-coder` belegt 15,6 von 16,3 GB und 10,4 von 12,3 GB; nach der Sitzung 0 | gemessen |
| Bilder | lesbar über Einfügen und über `Read` | gemessen, [modelle.md](modelle.md) |
| Absicherung | Server verlangt einen Schlüssel; ein Wächter sperrt zerstörerische Befehle und fragt bei heiklen nach. Befehle laufen weiter ohne Sandbox auf dem echten Rechner. | gemessen, [sicherheit.md](sicherheit.md) |
| Messbarkeit | neun Aufgaben (Python, PowerShell, Bild, langer Kontext, Umbau), jede mit Musterlösung und Selbsttest | gemessen, `Test-Tasks.ps1` |
| Regeltreue | `local-coder` hält mit Abschlussprüfung 89 % der geprüften Arbeitsregeln ein (vorher 65 %): README und Test 15 von 15, Wert in die Konfigurationsdatei 0 von 6, mit Projektvorlage 5 von 6. Kosten: etwa ein Viertel mehr Laufzeit als ohne Abschlussprüfung | gemessen, [modellwahl.md](modellwahl.md) |
| Arbeitsweise | `New-Project.ps1` legt Projekte mit `CLAUDE.md`, Prüfbefehl, Git-Hook und Entscheidungsordner an; Befehle `/lokal:feature`, `/lokal:bugfix`, `/lokal:pruefen` | gemessen, `Test-Templates.ps1`; Befehle nur an einer Aufgabe |

Die größten Lücken sind jetzt die ungeprüften Stellen: die Bedienung am Terminal (S8,
N8), die Linter im Prüfbefehl (N9) und der Wert in der Konfigurationsdatei ohne
Projektvorlage. Der Speicher ist mit 128k Kontext fast ausgeschöpft; mehr Tempo oder eine
größere Quantisierung gehen nur noch auf Kosten des Kontexts oder mit anderer Hardware.

## Härtung für echte Projekte (Vorrang seit 2026-11-16)

Bei echter Arbeit an einer ESP32-Firmware zeigte `local-coder` zwei Fehlerklassen, die der
Benchmark nicht misst: **erfundene Fakten** (Pins, Spannungen, Konfigurationsschlüssel)
und **Widersprüche zwischen Dateien** nach einer Änderung. Eine Gegenprüfung mit einem
großen Modell fand beides. Ziel des Nutzers: Projekte, die mit dem lokalen Coder
nachhaltig zuverlässig werden. Gleichstand eines 27B-Modells mit großen Modellen ist durch
Einstellungen nicht zu erreichen (Annahme, nicht gemessen); das Ziel gilt dem ganzen
System aus Modell, Regeln und Prüfprogrammen. Der Nutzer wählte am 2026-11-16 „Setup
härten“ und für den zweiten Blick die lokale Variante (A).

| Nr. | Schritt | Stand |
|---|---|---|
| H1 | Eine Quelle der Wahrheit je Projekt (`facts\facts.json`) und Abgleich gegen Doku und Code im Prüfbefehl | erledigt 2026-11-17 ([projekte.md](projekte.md)) |
| H2 | Regel „Fakten belegen statt raten“ in `entwicklungsregeln.md` und der `CLAUDE.md` der Vorlage | erledigt 2026-11-17; Wirkung nicht gemessen (H4) |
| H3 | Zweiter Blick: nach größeren Änderungen prüft ein zweites lokales Modell (`local-qwen38`) den Diff in frischem Kontext | erledigt 2026-11-17 ([agent.md](agent.md)); an einem Fall gemessen, `local-coder` fand dort als Prüfer mehr. Benchmark `h3-qwen38` nach 9 von 42 Läufen unterbrochen: 1 echter Befund, kein Fehlalarm, 53 % mehr Zeit. Offen: Rest der Aufgaben und `local-coder` als Prüfer (`h3-coder`) |
| H4 | Benchmark-Aufgaben für Faktentreue und Konsistenz über Dateien | Aufgaben `datenblatt` und `pinwechsel` erledigt 2026-11-17 ([erweitern.md](erweitern.md)); `local-coder` besteht beide 3 von 3, `fakten` 6 von 6 ([Protokoll](protokoll.md)). Offen: Vergleich ohne Faktenablage; Wirkung des zweiten Blicks mit `Benchmark-Models.ps1 -Git` |

## Reihenfolge

| Stufe | Inhalt | Aufwand | Ziel |
|---|---|---|---|
| 1 | Schutznetz: erledigt am 2026-11-15 ([Protokoll](protokoll.md), [sicherheit.md](sicherheit.md)). Rest: S8 | eine Sitzung am Terminal | Ein Fehler des Modells zerstört nichts auf dem Rechner, ein Tippfehler in `config\` fällt sofort auf |
| 2 | Messbarkeit: erledigt am 2026-11-15 ([Protokoll](protokoll.md), [modellwahl.md](modellwahl.md)) | | Jede spätere Änderung lässt sich an Aufgaben prüfen, die dem echten Einsatz gleichen |
| 3 | Arbeitsweise: erledigt am 2026-11-15 ([Protokoll](protokoll.md), [projekte.md](projekte.md), [agent.md](agent.md)). Rest: N8, N9, Q9 | | Jedes neue Projekt beginnt pflegbar, Tests und Prüfungen laufen ohne Zutun des Modells |
| 4 | Feinschliff, erster Teil erledigt am 2026-11-16 (E1, E2, G1, G2, Q9: [modellwahl.md](modellwahl.md)). Rest: E3 bis E5, G3, G4, Q4, Q5 (Q6 ist als H3 erledigt, G5 laufend) | je ein Messlauf | Mehr Kontext und Tempo, jeweils mit Zahl belegt |
| 5 | Größere Schritte: S6, S9, Q7, G6 | offen | Sandbox, Modellwechsel, Hardware |

## Sicherheit

Ein unzensiertes Modell lehnt nichts ab, auch keine Anweisung, die in einer gelesenen
Datei oder Webseite versteckt ist. Die Absicherung muss deshalb außerhalb des Modells
liegen: im Server, in Claude Code und in Git.

**Grundsatz (Vorgabe des Nutzers, 2026-11-15):** Der Schutz dient dem eigenen Rechner und
den eigenen Daten. Er bewertet nicht, woran das Modell arbeitet, und er behindert die
normale Arbeit nicht. Jeder Vorschlag unten ist daran zu messen; im Zweifel fragt der
Schutz nach, statt zu sperren.

Erledigt sind der Schlüssel für den Server, der Wächter vor jedem Werkzeug-Aufruf (auch
für Zugangsdaten) und der Git-Hinweis beim Start: [sicherheit.md](sicherheit.md).

| Nr. | Vorschlag | Warum | Prüfen |
|---|---|---|---|
| S5 | **Herkunft und Prüfsummen der Modelldateien.** Feld `sha256` je Datei in `models.json`, `Add-Model.ps1` prüft es. Quelle der drei `mmproj`-Dateien nachtragen. | Modelldateien sind fremder Code für die Grafikkarte. Bei den `mmproj`-Dateien ist die Quelle nicht festgehalten. | `Add-Model.ps1` lehnt eine Datei mit falscher Summe ab |
| S6 | **Riskante Arbeit in WSL2.** Claude Code in WSL2 mit eingeschalteter Sandbox (Schreiben nur im Projektordner, Netz nur zu erlaubten Adressen), `llama-server` bleibt unter Windows. Vorher den Schalter `--restricted` ausprobieren, der die Datei-Werkzeuge auf den Arbeitsordner beschränkt. | Einzige Möglichkeit, Befehle wirklich einzusperren (belegt). Aufwand: Netzwerk zwischen WSL2 und Windows, zweite Installation. | Schreibversuch außerhalb des Projektordners scheitert |
| S7 | **Abhängigkeiten prüfen, ohne die Arbeit aufzuhalten.** `pip-audit` oder `npm audit` im Prüfbefehl des Projekts (N9); keine Rückfrage bei jeder Installation. | Pakete aus dem Netz sind der übliche Weg für Schadcode auf dem eigenen Rechner; ein lokales Modell erfindet gelegentlich Paketnamen (Annahme). Eine Rückfrage bei jedem `pip install` würde die normale Arbeit behindern. | Ein Paket mit bekannter Lücke lässt die Projektprüfung scheitern |
| S8 | **Rückfrage in einer echten Sitzung bestätigen.** Im Terminal einen Befehl auslösen, bei dem der Wächter fragt (etwa `git reset --hard` in einem Testordner), und prüfen, dass die Frage mit Begründung erscheint und Ja wie Nein wirken. Danach `E:\LlamaCpp\logs\guard.log` nach einigen Tagen Arbeit durchsehen: Regeln, die bei normaler Arbeit anschlagen, lockern. | Geprüft sind bisher Sperren und Rückfragen in Läufen ohne Nutzer; dort zählt eine Rückfrage als Nein. Ob der Wächter im Alltag stört, zeigt nur der Alltag. | Frage erscheint; kein Eintrag im Protokoll des Wächters, der normale Arbeit betrifft |
| S9 | **Sperren schwerer umgehbar machen.** Skripte, die das Modell schreibt und dann startet, vor dem Start mit denselben Regeln prüfen. | Gemessen: Auf eine Sperre hin suchte das Modell von sich aus eine andere Schreibweise. Ein Wächter, der nur die Befehlszeile sieht, bemerkt nicht, was in einer gestarteten Datei steht. | Testfall: gesperrter Befehl in einer `.ps1`- oder `.sh`-Datei wird beim Start erkannt |

## Qualität

Erledigt sind die Aufgaben nach dem echten Einsatz und die Messung der Regeltreue
([erweitern.md](erweitern.md)), die Hinweise zu PowerShell 5.1 (`psscript` 9 von 9 statt
0 von 6) und die Abschlussprüfung ([agent.md](agent.md)). Ausgangswerte für alles Weitere,
`local-coder`, Lauf `stufe4`: 14 von 15 Läufen bestanden in 4903 s, 89 % der Regeln
eingehalten, `longcontext` 2 von 3.

| Nr. | Vorschlag | Warum | Prüfen |
|---|---|---|---|
| Q4 | **Denkaufwand begrenzen.** `reasoning-budget` in Stufen messen. | Offener Punkt aus dem Protokoll. Weniger Denk-Tokens sparen Zeit und Kontext; ob die Qualität leidet, ist offen (Annahme). | `planner` sechsmal je Stufe: Quote und Zeit |
| Q5 | **Größere Quantisierung.** Q5_K_M des 27B-Modells statt Q4_K_M. Die Datei ist geladen (Prüfsumme gleich der Angabe der Quelle), Profil `local-coder-q5`. Gemessen: passt nur mit 64k Kontext (Aufteilung 66/34), 54 statt 61 Tok./s. Offen ist der Vergleich der Qualität; ein Gewinn müsste den Verlust von 64k Kontext aufwiegen. | Mehr Bits je Gewicht heißt weniger Rechenfehler; ob das bei Agenten-Aufgaben sichtbar wird, ist offen (Annahme). Kostet Speicher und etwas Tempo. | `planner` und die fünf neueren Aufgaben, Tempo aus `Test-Model.ps1` |
| Q7 | **Modelle beobachten, mit festem Verfahren.** Einmal im Monat Kandidaten sichten (zuletzt genannt: Devstral Small 2, neuere Qwen-Coder-Modelle; Angaben der Hersteller, hier ungeprüft). Ein Wechsel nur, wenn das neue Modell den ganzen Benchmark mindestens so gut besteht. | Qwen 3.8 war laut Hersteller besser und in der eigenen Messung schlechter als Qwen 3.6 (gemessen). Eigene Messung schlägt Bestenlisten. | Eintrag in [modellwahl.md](modellwahl.md) je Kandidat |

## Nachhaltige Entwicklung

Der Coder soll Projekte bauen, die in zwei Jahren noch jemand versteht und erweitert. Dafür
reichen Regeln im Prompt nicht. Die Struktur muss im Projekt liegen, und die Prüfung muss
ein Programm übernehmen.

Erledigt sind die Projektvorlage mit `New-Project.ps1`, die kurze `CLAUDE.md`, der Ordner
für Entscheidungen, der Prüfbefehl mit Git-Hook, Schnittstellen und Versionen in der
Vorlage und die Befehle für feste Abläufe: [projekte.md](projekte.md). Gemessen: Mit
`CLAUDE.md` und Prüfbefehl hält `local-coder` 91 % der Regeln ein statt 85 %, der Wert in
der Konfigurationsdatei gelingt in 5 von 6 statt 0 von 6 Läufen.

| Nr. | Vorschlag | Warum | Prüfen |
|---|---|---|---|
| N8 | **Entscheidungsdateien und Befehle messen.** Eine Benchmark-Aufgabe, bei der eine Änderung an einer Schnittstelle eine Datei in `docs\entscheidungen\` verlangt; `/lokal:feature` und `/lokal:bugfix` an allen passenden Aufgaben; Befehle und Abschlussprüfung in einer echten Sitzung am Terminal ausprobieren. | Der Ordner und die Befehle sind da, aber ob das Modell Entscheidungen von sich aus festhält, ist nicht gemessen. `/lokal:feature` ist nur an `extend` gemessen (2 von 3, Regeln 15 von 15). | Quote je Befehl; Entscheidungsdatei in drei von drei Läufen |
| N9 | **Prüfbefehl ausbauen.** `ruff`, `PSScriptAnalyzer`, `gitleaks` und `pip-audit` (S7) installieren und die optionalen Schritte in `config\check.json` der Vorlagen ausprobieren; derselbe Befehl in GitHub Actions. | Die Linter-Schritte stehen in der Vorlage, sind aber ungeprüft, weil die Programme fehlen. Eine Suche nach Geheimnissen fehlt ganz. | Absichtlich eingebaute Fehler (unbenutzter Import, Schlüssel im Code) lassen den Befehl scheitern |
| N6 | **Kleine Schritte.** Ein Auftrag je Sitzung, danach `/clear`. Ein Commit je abgeschlossener Änderung. Große Vorhaben zuerst in einer Liste in `docs\` zerlegen, dann Punkt für Punkt. | 64k Kontext sind schnell voll; nach dem Komprimieren fehlen Einzelheiten. Kleine Commits lassen sich einzeln zurücknehmen. | Erfahrungswert, im Protokoll notieren |

## Effizienz

Knapp sind der Kontext und der Speicher der schnelleren Grafikkarte. Erledigt: Bild-Encoder
auf der RTX 3060 und 128k Kontext ([modellwahl.md](modellwahl.md)).

| Nr. | Vorschlag | Warum | Prüfen |
|---|---|---|---|
| E3 | **Ausgaben von Werkzeugen begrenzen.** Obergrenze für die Ausgabe von `Bash` senken; Regel: lange Ausgaben in eine Datei leiten und gezielt lesen. | Eine einzige lange Testausgabe kann mehrere tausend Tokens kosten (Annahme zur Größenordnung). | Tokens je Aufgabe im Benchmark |
| E4 | **Kontext-Cache über Pausen retten.** `slot-save-path` ausprobieren. | Nach der Leerlauf-Grenze und nach dem Entladen wird die Unterhaltung neu eingelesen: bei 60k Tokens etwa 40 s (gerechnet aus 1500 Tokens/s). | Zeit der ersten Antwort nach dem Aufwachen |
| E5 | **Systemprompt stabil halten.** Schalter `--exclude-dynamic-system-prompt-sections` und kürzere Werkzeugbeschreibungen prüfen. | Der Schalter verschiebt wechselnde Angaben aus dem Systemprompt (belegt, `claude --help`); ob der Cache des Servers dadurch öfter trifft, ist offen. Der Cache selbst arbeitet: Im Protokoll wurden von 6300 Tokens nur 385 neu eingelesen (gemessen). | Neu eingelesene Tokens je Anfrage im `server.log` |

## Geschwindigkeit

| Nr. | Vorschlag | Warum | Prüfen |
|---|---|---|---|
| G2 | **GPU-Aufteilung, falls Kontext frei wird.** 79/21 statt 70/30. | Gemessen bei 64k: 65,5 statt 61 Tok./s, Einlesen 1635 statt 1316 Tok./s. Der Speicher dafür ist seit 128k Kontext belegt; die Frage stellt sich neu mit G6 oder einem kleineren Kontext. | `Test-Model.ps1` |
| G3 | **Hintergrundanfragen.** Im `server.log` einer echten Sitzung zählen, wie oft Claude Code Nebenanfragen schickt und ob danach die ganze Unterhaltung neu eingelesen wird. Falls ja: zweiter Platz (`parallel = 2`) oder ein kleines Modell auf der 3060 für diese Anfragen. | Mit einem Platz kann eine Nebenanfrage den Cache der Hauptunterhaltung verdrängen (Annahme). In Läufen mit `-p` kommt das nicht vor. | Neu eingelesene Tokens je Anfrage |
| G4 | **Aufgaben verteilen.** `local-fast` für Suchen, Erklären und kleine Änderungen, `local-coder` für alles Schwere. | `local-fast` ist doppelt so schnell und besteht die leichten Aufgaben (gemessen), scheitert aber an `planner`. | Zeit je Aufgabenart |
| G5 | **llama.cpp aktuell halten.** Neue Versionen nach dem Verfahren in [backend.md](backend.md) einspielen. Zuletzt b12433 am 2026-11-16: 13 von 15 in 4463 s, 91 % Regeln, Tempo gleich ([Protokoll](protokoll.md)). | MTP und das Rechnen mit mehreren Karten werden laufend schneller. Nach jedem Wechsel den Benchmark wiederholen. | `Benchmark-Models.ps1 -Label <version>` |
| G6 | **Hardware.** Eine Karte mit 24 GB statt der RTX 3060, oder die zweite Karte an einen Steckplatz mit mehr Leitungen. | Der Anschluss mit PCIe x4 bremst ([gpu-tuning.md](gpu-tuning.md)). Mehr Speicher erlaubt Q5 oder Q6 zusammen mit 128k Kontext und die schnellere Aufteilung. Größter Hebel, einziger mit Kosten. MTP-Länge, Aufteilung und Kontext sind ausgeschöpft (gemessen). | Benchmark vorher und nachher |

## Pflege dieses Projekts

| Nr. | Vorschlag | Warum | Prüfen |
|---|---|---|---|
| P3 | **Tests für die Bausteine.** Pester-Tests für `lib\Config.ps1`, die erzeugte `models.ini` und `lib\Session.ps1`. | Bisher prüft nur der Lauf mit geladenem Modell. Die Logik darum herum wächst. | Tests laufen in `Test-Setup.ps1` mit |
| P4 | **Fehler an llama.cpp melden.** Die falsche Reihenfolge von Text und Tool-Ergebnis ([modelle.md](modelle.md)) als Issue. | Dann entfällt der Block „agent fix“ irgendwann, und die Vorlagen bleiben näher am Original. Braucht das GitHub-Konto des Nutzers. | Issue angelegt |
| P5 | **Offenes aus dem Protokoll.** `/model` und Continue in echter Bedienung bestätigen, Ablehnungsraten selbst prüfen, Einzelwirkung der Arbeitsregeln messen (Lauf mit und ohne `entwicklungsregeln.md`, Quote „Regeln eingehalten“). Im Benchmark abgelehnte Aufrufe ansehen: Das Modell schrieb den Arbeitsordner mit falscher Groß- und Kleinschreibung oder setzte `cd ... &&` vor den Befehl. | Stehen seit dem 14.11. offen. | Einträge im Protokoll |

## Quellen der Recherche

- Claude Code, Sandbox: <https://code.claude.com/docs/en/sandboxing> (Windows ohne Sandbox,
  Einstellungen der Sandbox)
- Unsloth, Claude Code mit lokalen Modellen: <https://unsloth.ai/docs/basics/claude-code>
  (Cache, Schalter für den Systemprompt, Sampling)
- llama.cpp, Dokumentation des Servers im Stand b12359: `tools/server/README.md`
  (Schlafen im Leerlauf, Router, Cache-Optionen), Quelltext `tools/server/server-chat.cpp`
- Stack Overflow Blog, „Coding guidelines for AI agents“:
  <https://stackoverflow.blog/2026/03/26/coding-guidelines-for-ai-agents-and-people-too/>
- Sonar, „Seven habits of highly effective AI coding“:
  <https://www.sonarsource.com/blog/seven-habits-of-highly-effective-ai-coding/>
- Marmelab, „Agent Experience“: <https://marmelab.com/blog/2026/01/21/agent-experience.html>
- Modellübersichten (Angaben der Hersteller, hier nicht nachgemessen):
  <https://insiderllm.com/guides/best-local-coding-models-2026/>,
  <https://www.promptquorum.com/local-llms/best-local-llms-for-coding>

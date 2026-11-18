# Modellwahl

Bewertung der Messwerte aus [benchmark.md](benchmark.md). Die jüngste Messung steht im ersten
Abschnitt, die Wahl der Modelle im Abschnitt „Aktuelle Wahl“. Die Abschnitte darunter sind älter und bleiben
als Begründung stehen.

## Agent: Unzensiert gegen Claude Code, alle Aufgaben dreimal (2026-11-18)

Lauf `vergleich2`: alle elf Aufgaben, jede dreimal, `local-coder`, ohne zweiten Blick, sonst
wie `vergleich1` (Abschnitt darunter). Diesmal lief `claude-local` zuerst (06:40 bis 08:30
Uhr), dann Unzensiert (08:30 bis 10:03 Uhr), damit eine Aufwärmphase oder die Wärme der
Karten nicht Unzensiert begünstigt. Je Aufgabe der Median von Zeit und Runden aus drei
Läufen, dazu die bestandenen Läufe. Ein Lauf am Zeitlimit zählt wie in
[benchmark.md](benchmark.md) als nicht bestanden, auch wenn seine Dateien die Prüfung
bestehen:

| Aufgabe | Unzensiert | claude-local (Claude Code) |
|---|---|---|
| `bugfix` | 29 s, 8 Runden, 3 / 3 | 35 s, 11 Runden, 3 / 3 |
| `feature` | 67 s, 17 Runden, 3 / 3 | 80 s, 21 Runden, 3 / 3 |
| `multifile` | 81 s, 21 Runden, 3 / 3 | 96 s, 32 Runden, 3 / 3 |
| `planner` | 187 s, 27 Runden, 3 / 3 | 293 s, 53 Runden, 2 / 3 (einmal Zeitlimit, Dateien richtig) |
| `extend` | 201 s, 23 Runden, **1 / 3** | 267 s, 37 Runden, 3 / 3 |
| `refactor` | 176 s, 31 Runden, 2 / 3 (einmal Zeitlimit, Dateien richtig) | 258 s, 54 Runden, 3 / 3 |
| `psscript` | 306 s, 54 Runden, 3 / 3 | 425 s, 56 Runden, 3 / 3 |
| `screenshot` | 85 s, 13 Runden, 3 / 3 | 89 s, 20 Runden, 3 / 3 |
| `longcontext` | 299 s, 41 Runden, 1 / 3 | 366 s, 74 Runden, 2 / 3 |
| `datenblatt` | 110 s, 18 Runden, 2 / 3 | 135 s, 30 Runden, 1 / 3 |
| `pinwechsel` | 88 s, 15 Runden, 3 / 3 | 116 s, 30 Runden, 3 / 3 |
| **zusammen** | **27 / 33 bestanden, 1.629 s, 268 Runden, 98.591 Tokens, Regeln 88 / 96** | **29 / 33 bestanden**, 2.160 s, 418 Runden, 122.004 Tokens, Regeln 86 / 96 |

„zusammen“ heißt bei Zeit, Runden und Tokens: Summe der Mediane je Aufgabe. Tokens sind die
vom Modell geschriebenen.

- **Tempo:** Unzensiert war bei allen elf Aufgaben schneller, zusammen 25 % weniger Zeit,
  36 % weniger Runden und 19 % weniger geschriebene Tokens. Über alle 66 Läufe gerechnet
  5.528 s gegen 6.541 s (15 % weniger, beide mit einer Zeitüberschreitung von 600 s). Das
  bestätigt `vergleich1`, jetzt mit Wiederholungen, allen Aufgaben und umgekehrter
  Reihenfolge.
- **Bestanden:** 27 gegen 29 von 33, mit den Dateien der Läufe am Zeitlimit 28 gegen 30.
  Der Unterschied liegt im Zufall dieser Stichprobe (exakter Test nach Fisher, p = 0,73).
  Alle Fehlschläge mit falschem Ergebnis sind Fehler des Modells, die auch bei Claude Code
  vorkommen:
  - `extend`, bei Unzensiert zweimal: `transfer` normalisiert den Artikelnamen nicht
    (`"Bolt"` statt `"bolt"`). Genau dieser Fehler (`only 0 of Bolt in main`) traf Claude
    Code in 2 von 28 bisherigen Läufen. Unzensiert hatte das neue Verhalten mit eigenen Skripten
    und 24 neuen Tests geprüft, nur nicht mit großgeschriebenem Namen.
  - `longcontext`: dieselben Fehler wie in früheren Läufen mit Claude Code (Spanien ohne
    `invoice`, Irland ohne Obergrenze). Claude Code bestand die Aufgabe über alle
    bisherigen Läufe in 6 von 24 Fällen.
  - `datenblatt`: bei beiden derselbe falsche Wert aus dem Datenblatt (HX-7).
- **Zeitüberschreitungen:** je eine, beide Lösungen bestanden trotzdem. Bei Unzensiert
  (`refactor` #1) lief das Modell sechs Minuten im Kreis: Es wollte seinen eigenen neuen
  Test reparieren, schrieb dieselbe Datei viermal mit gleichem Inhalt und versuchte 16
  Edits, die nichts änderten. Der Schutz gegen Wiederholungen griff nicht, weil jede
  Änderung an einer Datei seinen Zähler zurücksetzte, auch ein Write mit gleichem Inhalt,
  und weil die Testausgabe wegen der Laufzeit nie gleich aussah (`Ran 7 tests in 0.507s`,
  `0.493s`, `0.496s`, jedes Mal mit demselben `TypeError`).
- **Regeln:** 88 gegen 86 von 96, praktisch gleich. Bei beiden fehlte in allen Läufen
  `config` in `extend` und `psscript`; dazu bei Claude Code viermal `tests`, bei Unzensiert
  einmal `readme` und `tests`.

Nicht gemessen: der zweite Blick (`-Git`); sein Prüfer `local-qwen38` hieße einen
Modellwechsel bei jeder Aufgabe.

## Agent: Unzensiert gegen Claude Code (2026-11-17)

Derselbe Benchmark mit beiden Agenten, `local-coder`, gleicher Server, gleiche Werkzeuge
(`tools` in `config\agent.json`), gleiche erlaubten Befehle, gleiche Arbeitsregeln und
Abschlussprüfung, Lauf `vergleich1`, je ein Lauf, ohne zweiten Blick
([unzensiert.md](unzensiert.md)):

| Aufgabe | Unzensiert | claude-local (Claude Code) |
|---|---|---|
| `screenshot` | 80 s, 16 Runden | 98 s, 22 Runden |
| `pinwechsel` | 80 s, 17 Runden | 123 s, 30 Runden |
| `datenblatt` | 105 s, 15 Runden | 124 s, 25 Runden |
| `extend` | 214 s, 21 Runden | 244 s, 34 Runden |
| `refactor` | 180 s, 19 Runden | 240 s, 48 Runden |
| **zusammen** | **5 / 5 bestanden, 659 s, 88 Runden, 42.640 Tokens, Regeln 22 / 23** | 5 / 5 bestanden, 829 s, 159 Runden, 48.858 Tokens, Regeln 21 / 23 |

Unzensiert war bei allen fünf Aufgaben schneller (zusammen 20 % weniger Zeit), brauchte
45 % weniger Runden und 13 % weniger geschriebene Tokens; beide bestanden alles. Die
verfehlten Regeln: bei beiden `config` in `extend`, bei `claude-local` zusätzlich
`docstrings` in `refactor`.

Vorbehalte: **ein Lauf je Aufgabe.** Frühere Wiederholungen derselben Aufgabe mit
`claude-local` streuten um bis zu 30 % (`extend` 241 bis 334 s im Lauf `stufe4`), der
Abstand einer einzelnen Aufgabe liegt also in der Streuung; dass er bei allen fünf in
dieselbe Richtung geht, spricht für einen echten Unterschied, belegt ihn aber nicht. Runden
sind bei Unzensiert die Anfragen an das Modell, bei Claude Code dessen Angabe `num_turns`.
Nicht gemessen: `longcontext` (Zusammenfassen bei vollem Kontext), `psscript`, die älteren
Aufgaben, Wiederholungen (`-Repeat 3`) und der zweite Blick (`-Git`).

## Faktentreue und Konsistenz über Dateien (2026-11-17)

Zwei neue Aufgaben nach den Fehlerklassen aus echter Firmware-Arbeit
([erweitern.md](erweitern.md)), `local-coder`, je dreimal, Lauf `h4`:

| Aufgabe | Bestanden | Zeit für 3 Läufe | Regeln | davon `fakten` |
|---|---|---|---|---|
| `datenblatt` (Treiber nach Datenblatt eines erfundenen Sensors) | 3 / 3 | 448 s | 12 / 15, nach Korrektur der Regelprüfung 15 / 15 | 3 / 3 |
| `pinwechsel` (Pins an fünf Stellen stimmig verlegen) | 3 / 3 | 338 s | 15 / 15 | 3 / 3 |

Mit Datenblatt und Faktenablage im Projekt liest `local-coder` nach, statt vom Vorgänger
abzuschreiben, und hält Pins über alle Stellen stimmig. Ob das an Faktenablage und Regel
liegt oder an der überschaubaren Größe der Aufgaben, trennt die Messung nicht.
Vergleichsläufe ohne Faktenablage und mit zweitem Blick (`-Git`) stehen aus. Einzelheiten:
[Protokoll](protokoll.md) vom 2026-11-17.

## Feinschliff: Kontext, Speicher, Abschlussprüfung (2026-11-16)

Stufe 4 des [Zukunftsplans](roadmap.md), erster Teil. Rohwerte aus je drei bis fünf
Messungen von `local-coder`, Aufgaben wie im Abschnitt darunter.

| Punkt | Gemessen | Entscheidung |
|---|---|---|
| E1 Bild-Encoder auf die RTX 3060 (`mmproj-device`) | 5070 Ti 13,6 statt 14,8 GB, 3060 8,7 statt 7,6 GB; Bild-Test 2,4 bis 2,8 s wie vorher; Tempo gleich | bleibt, alle drei Profile |
| E2 Kontext | 96k: 14,6 und 9,6 GB; 128k: 15,6 und 10,4 GB; Tempo gleich (59 bis 65 Tok./s). 32k kosten etwa 1,0 GB auf der 5070 Ti und 0,85 GB auf der 3060. Mit 128k laden auch `local-fast` (14,9 und 11,5 GB, 131 Tok./s) und `local-qwen38` (15,3 und 10,2 GB, 55 Tok./s) | 128k für alle drei |
| G2 GPU-Aufteilung bei 64k | 70/30: 61 Tok./s, Einlesen 1316; 73/27: 62,6 und 1448; 76/24: 64,5 und 1578; 79/21: 65,5 und 1635; 82/18 lädt nicht | bleibt 70/30: Der Speicher der 5070 Ti geht an den Kontext |
| G1 MTP-Länge (`spec-draft-n-max`) | 2: 52,0 Tok./s (80 % angenommen); 3: 59,4 (72 %); 4: 61 bis 62 (63 %); 6: 57,4 (50 %); 8: 50,5 (41 %) | bleibt 4 |
| Q5 größere Quantisierung (Q5_K_M) | lädt mit 64k bei Aufteilung 66/34 (14,4 und 10,1 GB): 54 Tok./s, Einlesen 1152; mit 96k bei 70/30 lädt sie nicht | Profil `local-coder-q5` zum Vergleich; Qualität nicht gemessen |

Die fünf Aufgaben je dreimal, `local-coder`:

| | `stufe3b` (64k) | `stufe4` (128k, Encoder auf der 3060, Erinnerung nur für offene Punkte) |
|---|---|---|
| `extend` | 3 / 3 (348, 377, 402 s) | 3 / 3 (334, 245, 241 s) |
| `refactor` | 3 / 3 (400, 290, 503 s) | 3 / 3 (264, 248, 244 s) |
| `psscript` | 3 / 3 (572, 553, 507 s) | 3 / 3 (446, 636, 566 s) |
| `screenshot` | 3 / 3 (128, 102, 135 s) | 3 / 3 (113, 138, 146 s) |
| `longcontext` | 0 / 3 (554, 363, 717 s) | 2 / 3 (494, 382, 406 s) |
| **Bestanden** | **12 / 15** in 5951 s | **14 / 15** in 4903 s |
| `readme` | 13 / 15 | 15 / 15 |
| `tests` | 13 / 15 | 15 / 15 |
| `config` | 0 / 6 | 0 / 6 |
| **Regeln eingehalten** | **56 / 66 (85 %)** | **59 / 66 (89 %)** |

Davor lief `longcontext` allein dreimal mit 128k und der alten Erinnerung (Lauf
`stufe4-128k`): 1 / 3 bestanden, die anderen mit 1 und 2 falschen von 21 Ländern, alle
drei regulär beendet. Die Zeit des zweiten Laufs (41474 s) ist unbrauchbar: Der Rechner
ging währenddessen in den Ruhezustand.

Bewertung:

- **128k Kontext lösen den Abbruch der langen Aufgabe.** In sechs Läufen mit 128k endete
  jeder regulär, drei bestanden; mit 64k bestand keiner von zwölf, und mehrere brachen am
  vollen Kontext ab. Die Fehler, die bleiben, sind einzelne
  übersehene Regeln (Irland: zu schweres Paket bei kostenlosem Versand).
- **Die sparsamere Erinnerung kostet keine Regeltreue.** README und Test in 15 von 15
  Läufen, bei 18 % weniger Laufzeit. Wie viel davon auf die Erinnerung und wie viel auf
  den Kontext entfällt, trennt die Messung nicht; `extend` und `refactor`, die den Kontext
  nicht füllen, wurden 32 % schneller (1576 statt 2320 s).
- **`config` bleibt ohne Projektvorlage bei 0 von 6.** Das leistet die `CLAUDE.md`
  (Abschnitt darunter).
- **Grenzen:** drei Läufe je Aufgabe; zwei Änderungen zugleich; `local-fast` und
  `local-qwen38` sind mit 128k nur geladen und auf Tempo gemessen, nicht an den Aufgaben.
  Die Tab-Vervollständigung von Continue neben `local-coder` mit 128k ist nicht geprüft
  (auf der 3060 sind noch etwa 1,8 GB frei).

## Arbeitsweise: Hinweise, Abschlussprüfung, Projektvorlage (2026-11-15 abends)

Dieselben fünf Aufgaben, nur `local-coder`, je dreimal. Verglichen wird der Stand von
Stufe 2 mit drei Ausbaustufen ([agent.md](agent.md), [projekte.md](projekte.md)):

| Lauf | Was gilt |
|---|---|
| `stufe2` | Ausgangswert: nur die Arbeitsregeln |
| `stufe3` | dazu Hinweise zu PowerShell 5.1, Abschlussprüfung mit der ersten Fassung der Erinnerung, Befehle geladen |
| `stufe3b` | wie `stufe3`, Erinnerung geschärft (ein gelöschtes Prüfskript zählt nicht als Test, Konstanten gehören in die Konfigurationsdatei) |
| `stufe3-projekt` | wie `stufe3b`, dazu im Arbeitsordner eine kurze `CLAUDE.md` und der Prüfbefehl `scripts\Check.ps1`, wie in einem Projekt aus `New-Project.ps1` (`-Overlay projekt`) |

| | `stufe2` | `stufe3` | `stufe3b` | `stufe3-projekt` |
|---|---|---|---|---|
| `extend` | 3 / 3 | 2 / 3 | 3 / 3 | 3 / 3 |
| `refactor` | 3 / 3 | 3 / 3 | 3 / 3 | 3 / 3 |
| `screenshot` | 3 / 3 | 3 / 3 | 3 / 3 | 2 / 3 |
| `psscript` | 0 / 3 | 3 / 3 | 3 / 3 | 3 / 3 |
| `longcontext` | 0 / 3 | 0 / 3 | 0 / 3 | 0 / 3 |
| **Bestanden** | **9 / 15** | **11 / 15** | **12 / 15** | **11 / 15** |
| Zeit für 15 Läufe | 3970 s | 5494 s | 5951 s | 6555 s |
| `readme` | 7 / 15 | 14 / 15 | 13 / 15 | 12 / 15 |
| `tests` | 6 / 15 | 7 / 15 | 13 / 15 | 13 / 15 |
| `config` | 0 / 6 | 0 / 6 | 0 / 6 | 5 / 6 |
| `docstrings`, `headers`, `nodeadcode` | 30 / 30 | 30 / 30 | 30 / 30 | 30 / 30 |
| **Regeln eingehalten** | **43 / 66 (65 %)** | **51 / 66 (77 %)** | **56 / 66 (85 %)** | **60 / 66 (91 %)** |

Rohwerte in diesen Läufen: 58 bis 61 Tok./s.

Dazu ein kleiner Lauf `stufe3-befehl`: `extend` dreimal, Auftrag mit `/lokal:feature`
davor, ohne Projektvorlage: 2 / 3 bestanden in 914 s, Regeln 15 / 15, darunter `config`
3 / 3. Zum Vergleich `extend` in `stufe3b`: 3 / 3 in 1127 s, Regeln 12 / 15, `config` 0 / 3.

Bewertung:

- **Die Hinweise zu PowerShell 5.1 wirken.** `psscript` besteht in allen neun Läufen seit
  den Hinweisen, davor in keinem von sechs.
- **Die Abschlussprüfung bringt die README, erst die geschärfte Fassung auch die Tests.**
  Nach der ersten Fassung prüfte das Modell die neue Logik mit Wegwerf-Skripten und löschte
  sie wieder; `tests` stieg nur von 6 auf 7. Seit die Erinnerung das ausdrücklich nennt,
  stehen Tests in 13 von 15 Läufen im Projekt.
- **Den Wert in die Konfigurationsdatei bringt erst ein konkreter Hinweis.** Allgemeine
  Regel und Erinnerung: 0 von 18. Mit einer `CLAUDE.md`, die sagt, wo Einstellungen liegen
  und wer sie liest: 5 von 6. Mit dem Ablauf `/lokal:feature`: 3 von 3.
- **Der Preis ist Zeit.** 50 % mehr Laufzeit mit der geschärften Erinnerung, 65 % mehr mit
  Projektvorlage. Am teuersten ist `psscript` mit Projektvorlage: 842 bis 900 s statt
  507 bis 572 s; ein Lauf erreichte das Zeitlimit, einer füllte den Kontext
  (`blocking_limit`). Beide hatten die Aufgabe da schon gelöst.
- **`longcontext` bleibt bei 0 von 12.** Von den sechs Läufen in `stufe3b` und `stufe3-projekt` endeten drei regulär, mit 1, 3
  und 2 falschen von 21 Ländern; die anderen drei brachen am vollen Kontext ab
  (`rapid_refill_breaker`, `blocking_limit`). Die Arbeitsweise löst das nicht; es bleibt
  eine Frage des Kontexts (E2 im [Zukunftsplan](roadmap.md)).
- **Die übrigen Fehlschläge sind echte Fehler des Modells:** `extend` in `stufe3` und
  `stufe3-befehl` (Umbuchen scheitert in einem der geprüften Fälle), `screenshot` in
  `stufe3-projekt` (`0.5h` aus dem Bild nicht umgesetzt).
- **Grenzen der Messung:** drei Läufe je Aufgabe, ein Modell. Unterschiede von einem Lauf
  (11, 12, 11 von 15) sind Zufall. In `stufe3` wurden Hinweise, Abschlussprüfung und
  geladene Befehle zugleich eingeführt; ihre Wirkung lässt sich nur über die Aufgaben
  trennen (`psscript` für die Hinweise, `readme` und `tests` für die Prüfung). Die
  Regelprüfung bleibt mechanisch. `/lokal:feature` ist nur an einer Aufgabe gemessen,
  `/lokal:bugfix` und `/lokal:pruefen` gar nicht. Die `CLAUDE.md` der Messung ist von Hand
  für die Aufgaben geschrieben, nach dem Muster der Vorlage.

## Schwerere Aufgaben und Arbeitsregeln (2026-11-15)

Fünf neue Aufgaben, die dem echten Einsatz gleichen ([erweitern.md](erweitern.md)), je
dreimal, Lauf `stufe2`. Die Wahl vom 2026-11-14 (Abschnitt „Aktuelle Wahl“) bleibt bestehen und
ist jetzt breiter belegt.

| Aufgabe | `local-coder` | `local-fast` |
|---|---|---|
| `extend` (Projekt erweitern, Altes muss weiter gehen) | 3 / 3 (251, 191, 171 s) | 1 / 3 (186, 189, 119 s) |
| `refactor` (Umbau über sieben Dateien) | 3 / 3 (319, 216, 187 s) | 2 / 3 (120 s, Zeitlimit 600 s, 98 s) |
| `screenshot` (Fehler steht nur im Bild) | 3 / 3 (88, 75, 67 s) | 0 / 3 (41, 31, 72 s) |
| `psscript` (PowerShell 5.1) | 0 / 3 (465, 431, 356 s) | 0 / 3 (240 s, Zeitlimit 900 s, 548 s) |
| `longcontext` (15 Änderungen an 20 Modulen) | 0 / 3 (278, 557, 318 s) | 0 / 3 (305, 108, 122 s) |
| **Summe** | **9 / 15** in 3970 s | **3 / 15** in 3679 s |
| Regeln eingehalten | 43 / 66 (65 %) | 34 / 66 (52 %) |

Rohwerte in diesem Lauf: `local-coder` 63 Tok./s, `local-fast` 129 Tok./s.

Eingehaltene Arbeitsregeln je Regel (was die Regeln bedeuten: [erweitern.md](erweitern.md)):

| Regel | `local-coder` | `local-fast` |
|---|---|---|
| `readme` (README nennt das Neue) | 7 / 15 | 4 / 15 |
| `tests` (Test für das Neue) | 6 / 15 | 2 / 15 |
| `config` (neuer Wert in der Konfigurationsdatei) | 0 / 6 | 0 / 6 |
| `docstrings` (Beschreibung an neuen Funktionen) | 12 / 12 | 11 / 12 |
| `headers` (Kopfkommentar in neuen Skripten) | 3 / 3 | 2 / 3 |
| `nodeadcode` (kein auskommentierter Code) | 15 / 15 | 15 / 15 |

Bewertung:

- **`local-coder` bleibt Standard.** Erweitern, Umbauen und Fehler aus einem Bild beheben
  gelingen ihm in jedem Lauf. `local-fast` ist doppelt so schnell beim Antworten, besteht
  aber nur 3 von 15 Läufen und meldet auch die misslungenen als fertig.
- **`local-fast` liest das Bild, aber nicht genau.** In allen drei Läufen von `screenshot`
  nannte es beide Fehler richtig und behob sie, übersah aber die dritte Schreibweise
  (`0.5h`) im selben Aufruf des Bildschirmfotos.
- **PowerShell 5.1 ist die schwächste Stelle beider Modelle** (0 von 6). Jeder Lauf
  scheiterte an einer anderen Eigenheit: Fehlermeldung auf der Standardausgabe statt auf
  stderr, Exit-Code 1 statt 2, `total: null` oder ein Objekt statt einer Liste bei genau
  einem Eintrag, eine zusätzliche Ausgabezeile. Die Skripte waren jeweils fast richtig.
- **`longcontext` scheitert am Kontext, nicht am Können.** In vier der sechs Läufe brach
  Claude Code mit „Autocompact is thrashing“ ab: Der Kontext von 64k war direkt nach dem
  Komprimieren wieder voll. Die zwei Läufe, die durchliefen, hatten 14 von 15 und 13 von 15
  Änderungen richtig. Das spricht für mehr Kontext (E2 im [Zukunftsplan](roadmap.md)).
- **Die Arbeitsregeln wirken nur zum Teil.** Was beim Schreiben von Code nebenbei entsteht
  (Beschreibungen, kein toter Code), stimmt fast immer. Was ein eigener Schritt ist (README,
  Test, Wert in die Konfigurationsdatei), geschieht bei `local-coder` in weniger als der
  Hälfte der Läufe, der Wert in der Konfigurationsdatei nie.
- **Grenzen der Messung:** drei Läufe je Aufgabe sind wenig; die Regelprüfung ist eine
  mechanische Näherung (sie sieht, ob eine README geändert wurde, nicht ob der Text gut
  ist); `local-qwen38` wurde auf den neuen Aufgaben nicht gemessen.

## Aktuelle Wahl (2026-11-14 abends)

Seit dem Umbau auf llama.cpp kommt jede GGUF-Datei in Frage, nicht nur der Katalog von
Ollama. Drei Kandidaten wurden gegen das bisherige Standardmodell gemessen, alle mit dem
schlanken Werkzeugsatz ([agent.md](agent.md)), jede Aufgabe dreimal je Lauf.

| Profil | Modell | Leichte Aufgaben (9 Läufe) | `planner` (3 Läufe je Durchgang) | Antwort-Tempo | Unzensiert |
|---|---|---|---|---|---|
| **`local-coder`** | Qwen 3.6 27B Heretic v2 | 9 / 9 in 673 s ¹, 9 / 9 in 327 s | 3 / 3 in 461 s, 3 / 3 in 474 s | 60 Tok./s | ja |
| `local-fast` | Qwen 3.6 35B-A3B Heretic | 9 / 9 in 266 s | 1 / 3 in 846 s | 83 Tok./s ² | ja |
| `local-qwen38` | Qwen 3.8 27B Heretic (Standard bis dahin) | 9 / 9 in 375 s | 3 / 3 in 904 s, 2 / 3 in 1521 s | 50 bis 55 Tok./s | ja |
| ohne Profil | gpt-oss 20B | 9 / 9 in 166 s | 1 / 3 in 237 s | 211 Tok./s | nein |
| ohne Profil | qwen3-coder 30B (früher `local-fast`) | 7 / 9 in 1709 s ³ | nicht gemessen | 145 Tok./s | nein |

¹ Im ersten Durchgang direkt nach einem Neustart des Servers lag das Antwort-Tempo bei
37 statt 60 Tok./s. Die Ursache ist nicht geprüft; der zweite Durchgang zeigt den üblichen Wert.
² Im Benchmark gemessen. `Test-Model.ps1` zeigt mit seinem kurzen Prompt 141 Tok./s.
³ Mit dem vollen Werkzeugsatz, Zeitlimit 420 s. Mit dem schlanken Satz lief es ebenfalls in
die Schleife, der Lauf wurde abgebrochen.

Bewertung:

- **Die leichten Aufgaben trennen nicht mehr.** Alle brauchbaren Modelle bestehen sie. Die
  neue Aufgabe `planner` (Fehler in zwei Modulen nach Spezifikation beheben, ein Modul und
  einen Befehl ergänzen, versteckte Randfälle) trennt deutlich.
- **Qwen 3.6 27B ist das zuverlässigste Modell und bei `planner` am schnellsten.** Sechs von
  sechs Läufen bestanden, 135 bis 189 s je Lauf. Qwen 3.8 27B bestand fünf von sechs und
  brauchte 216 bis 600 s; ein Lauf überschritt das Zeitlimit, obwohl die Dateien schon
  richtig waren. Es denkt länger, ohne dass das Ergebnis besser wird. Qwen 3.6 kommt
  außerdem mit seiner eingebauten Chat-Vorlage aus.
- **Die schnellen Modelle scheitern an der schwereren Aufgabe.** Qwen 3.6 35B-A3B und
  gpt-oss 20B bestanden je einen von drei Läufen. gpt-oss hinterließ einmal eine Datei mit
  Syntaxfehler und hörte einmal nach drei Runden auf, ohne das neue Modul anzulegen.
- **Sechs Läufe je Modell sind wenig.** Der Abstand zwischen den beiden 27B-Modellen bei der
  Zeit ist in beiden Durchgängen gleich gerichtet; der Unterschied von einem nicht
  bestandenen Lauf allein wäre kein Beleg.
- **Nicht geprüft:** wie oft die Modelle Anfragen ablehnen. Die Angaben „unzensiert“ stammen
  von den Modellkarten.

**Entscheidung:**

- `local-coder` (Kurzname `unzensiert`) ist jetzt Qwen 3.6 27B Heretic v2.
- `local-fast` (`schnell`) ist jetzt Qwen 3.6 35B-A3B Heretic: für einfache, klar umrissene
  Aufträge, bei denen das Tempo zählt. Anders als der Vorgänger ist es unzensiert und endet
  zuverlässig.
- `local-qwen38` (`qwen38`) bleibt zum Vergleich wählbar.
- gpt-oss 20B und qwen3-coder 30B haben kein Profil mehr. Die Datei von qwen3-coder 30B ist
  gelöscht; die von gpt-oss 20B liegt als Hardlink noch in `E:\LlamaCpp\models`.

Quellen der Kandidaten:
[Qwen3.6-27B Heretic v2](https://huggingface.co/llmfan46/Qwen3.6-27B-uncensored-heretic-v2-Native-MTP-Preserved-GGUF),
[Qwen3.6-35B-A3B Heretic](https://huggingface.co/llmfan46/Qwen3.6-35B-A3B-uncensored-heretic-Native-MTP-Preserved-GGUF).

In `benchmark.md` und `results.jsonl` tragen die Messungen die heutigen Profilnamen: Was
als `cand-qwen36-27b`, `cand-qwen36-35b`, `cand-gpt-oss-20b` und unter den alten
Bedeutungen von `local-coder` und `local-fast` gemessen wurde, steht dort als `local-coder`,
`local-fast`, `gpt-oss-20b`, `local-qwen38` und `qwen3-coder-30b`.

### Warum qwen3-coder 30B nicht aufhörte

Die Ursache der Schleife ist gefunden. qwen3-coder 30B beendet seine Schlussantwort oft mit
einem angefangenen `<tool_call>` und dem Ende-Zeichen. Sobald der Text `<tool_call>` erscheint,
schaltet llama.cpp eine Grammatik ein, die einen vollständigen Werkzeugaufruf erzwingt. Das
Modell darf an dieser Stelle nicht mehr aufhören und ruft irgendein Werkzeug auf; nach dessen
Ergebnis wiederholt sich das. Ollama hat den angefangenen Aufruf stillschweigend verworfen,
deshalb trat es dort nicht auf.

Das Verhalten lässt sich ohne Claude Code mit einer einzelnen Anfrage nachstellen. Weniger
Werkzeuge ändern nichts daran, und `llama-server` hat keine Option, die erzwungene Grammatik
abzuschalten. Die Lösung war deshalb ein anderes Modell.

## Stand nach dem Umbau auf llama.cpp (2026-11-14 nachmittags)

In diesem und den folgenden Abschnitten meint `local-coder` Qwen 3.8 27B Heretic (heute
`local-qwen38`) und `local-fast` qwen3-coder 30B.

Lauf `llamacpp`: beide Profile, jede Agenten-Aufgabe dreimal, llama.cpp Build b12359.

| Profil | Bestanden | Zeit für 9 Läufe | Antwort-Tempo | Prompt-Tempo | Vergleich Ollama |
|---|---|---|---|---|---|
| **`local-coder`** (`unzensiert`) | 9 / 9 | 431 s | 58 Tok./s | 1488 Tok./s | 9 / 9 in 993 s, 58 Tok./s, 949 Tok./s (Lauf `repeat3`) |
| `local-fast` (`schnell`) | 7 / 9 | 1709 s | 145 Tok./s | 3835 Tok./s | 3 / 3 in 172 s (ein Lauf je Aufgabe), 140 Tok./s, 2744 Tok./s |

Bewertung:

- **`local-coder` ist über llama.cpp deutlich schneller fertig:** 431 s statt 993 s für
  dieselben neun Läufe, alle bestanden. Das Antwort-Tempo je Token ist etwa gleich geblieben
  (in Einzelmessungen 50 bis 68 Tok./s). Schneller geworden ist das Lesen des Prompts (etwa
  1490 statt 950 Tok./s), und die Läufe brauchten weniger Runden (im Mittel 9,8 statt 11,3).
- **Der Vergleich ist nicht sauber.** Zwischen den beiden Läufen haben sich mehrere Dinge
  zugleich geändert: Backend, GPU-Aufteilung (70:30 statt 65:35), Chat-Vorlage, die neuen
  Arbeitsregeln im Systemprompt und möglicherweise die Version von Claude Code. Welcher Anteil worauf
  zurückgeht, ist nicht gemessen.
- **`local-fast` ist über llama.cpp schlechter.** Ein Lauf lieferte ein falsches Ergebnis,
  einer überschritt das Zeitlimit, und die bestandenen Läufe der Aufgabe `bugfix` brauchten
  214 bis 300 s. Das Modell löst die Aufgabe, hört danach aber nicht auf: Es ruft weiter
  Werkzeuge auf (`ReportFindings`, Notizen ins Memory-Verzeichnis, `Skill`), bis zu 56 Runden.
  Derselbe Auftrag über Ollama am selben Tag: 40 s, 13 Runden (ein Lauf). Ohne die
  Arbeitsregeln trat das Verhalten ebenfalls auf (ein Lauf, Zeitlimit). Die Ursache ist
  **nicht geklärt**; Sampling-Werte und Chat-Vorlage wurden geprüft und sind unauffällig.
  Für `schnell` gilt bis dahin: in der Sitzung beobachten und abbrechen, wenn es nach der
  Lösung weiterläuft.
- **Empfehlung:** `local-coder` bleibt Standard und ist jetzt auch bei der Zeit je Aufgabe
  das schnellere Profil.

Ein erster Lauf mit dem Label `llamacpp` (in `results.jsonl` noch enthalten, im Bericht durch
den zweiten ersetzt) war verfälscht: Der Arbeitsordner lag im Repository, und Claude Code lud
dessen `CLAUDE.md` in die Aufgaben. Seitdem liegt der Arbeitsordner außerhalb
(`workDir` in `config\benchmark.json`).

## Ergebnis in Kürze (Ollama, Läufe vom 2026-11-13)

Jede Agenten-Aufgabe lief **genau einmal**. Ein einzelner Lauf ist wegen der Zufälligkeit der
Modelle nur ein Anhaltspunkt, vor allem bei den Zeiten. Für die drei unzensierten Modelle mit MTP
gibt es eine Wiederholungsmessung vom 2026-11-14, siehe unten; sie widerspricht der Rangfolge der
Zeiten in dieser Tabelle.

| Profil | Modell | Aufgaben | Zeit für alle drei | Antwort-Tempo ¹ | Unzensiert |
|---|---|---|---|---|---|
| `local-fast` (`schnell`) | `qwen3-coder:30b` | 3 / 3 | 172 s | 137 Tok./s | nein |
| – | `qwen3.8:27b` | 3 / 3 | 252 s | 60 Tok./s | nein |
| **`local-coder`** (`unzensiert`) | `unc-heretic` | 3 / 3 | 653 s | 55 Tok./s | ja |
| entfernt | `unc-blackfrost` | 3 / 3 | 289 s | 55 Tok./s | ja |
| entfernt | `unc-coletti` | 3 / 3 | 326 s | 53 Tok./s | ja |
| entfernt | `qwen3.8-EfficientThink-uncensored:27b` | 3 / 3 | 536 s | 26 Tok./s | ja |

¹ Mit der eingestellten GPU-Aufteilung 65:35, leerer Kontext. Siehe [gpu-tuning.md](gpu-tuning.md).

**Entscheidung (2026-11-14):** `local-coder` beruht jetzt auf `unc-heretic`. In der
Wiederholungsmessung (siehe unten) bestand es wie die anderen alle Läufe, hatte die
gleichmäßigsten Zeiten und lehnt laut Modellkarte am wenigsten ab (0–1 %). `unc-blackfrost`,
`unc-coletti` und das erste unzensierte Modell (`local-legacy`) wurden gelöscht, ebenso die
GGUF-Dateien; für einen erneuten Test müssen sie neu geladen werden.

**Entscheidung (2026-11-13), überholt:** `local-coder` beruhte auf `unc-blackfrost`. Es ist doppelt so
schnell wie das bisherige unzensierte Modell, bestand alle Aufgaben in der kürzesten Zeit der
unzensierten Kandidaten und lehnt laut Modellkarte 2,4 % ab. Für das reine Tempo gibt es `local-fast`.

## Unzensierte Modelle mit MTP

Die offiziellen Qwen-3.8-Modelle enthalten einen MTP-Kopf (Multi-Token Prediction): Das Modell
rät mehrere Tokens voraus und prüft sie in einem Schritt. llama.cpp nutzt das als spekulatives
Dekodieren, wenn das Profil `draft_num_predict` setzt. Das verdoppelt das Tempo (gemessen:
`qwen3.8:27b` 28 Tok./s ohne, 60 Tok./s mit MTP). Die bisherige unzensierte Variante hat
den MTP-Kopf beim Umbau verloren.

Drei unzensierte Varianten mit eingebettetem MTP-Kopf wurden von Hugging Face geladen und mit
`scripts\Import-Gguf.ps1` importiert (Einstellungen von `qwen3.8:27b` übernommen). Alle in Q4_K_M:

| Ollama-Name | Quelle | Verfahren | Ablehnungen laut Karte | MTP-Treffer |
|---|---|---|---|---|
| `unc-blackfrost` | Blackfrost-AI/Qwen3.8-27B-ABLITERATED-GGUF | Abliteration | 2,4 % | 70–76 % |
| `unc-heretic` | 0bserverx/Qwen3.8-27B-Heretic-Abliterated-Uncensored-GGUF (`RVN-Q4_K_M-mtp.gguf`) | Heretic/ARA, sehr nah am Original | 0–1 % | 72–78 % |
| `unc-coletti` | JonathanColetti/Qwen3.8-27B-Uncensored-GGUF | Heretic | 12 % | 77–78 % |

Die Ablehnungsraten stammen von den Modellkarten und wurden hier nicht nachgeprüft. Alle drei
bestanden die Agenten-Aufgaben. Die Zeitunterschiede (289 s bis 653 s) entstehen vor allem durch
unterschiedlich lange Denkphasen und Rundenzahlen, nicht durch das Token-Tempo, das bei allen
gleich ist.

### Wiederholungsmessung (2026-11-14, Lauf `repeat3`)

Jede der drei Aufgaben lief je Modell dreimal, also neun Läufe je Modell. Zusammen mit dem
Einzellauf vom 13.11. sind das vier Durchgänge.

| Modell | Bestanden | Zeit je Durchgang (alle drei Aufgaben) | Mittel aus 4 Durchgängen ² | Spanne je Aufgabe | Runden je Aufgabe |
|---|---|---|---|---|---|
| `unc-coletti` | 9 / 9 | 363 s, 263 s, 389 s | 335 s | 65–181 s | 15,7 |
| `unc-heretic` | 9 / 9 | 350 s, 334 s, 309 s | 412 s | 59–156 s | 11,3 |
| `unc-blackfrost` | 9 / 9 | 706 s, 638 s, 331 s | 491 s | 65–412 s | 14,2 |

² Einschließlich des Einzellaufs vom 13.11. (326 s, 653 s, 289 s).

Bewertung:

- **In der Qualität gibt es keinen messbaren Unterschied.** Alle drei bestanden jeden der zwölf
  Läufe, kein Lauf überschritt das Zeitlimit von 420 s.
- **Die Rangfolge vom 13.11. hat sich nicht bestätigt.** `unc-blackfrost` war im Einzellauf am
  schnellsten und ist in der Wiederholung am langsamsten und am unruhigsten: Ein Lauf der Aufgabe
  `feature` brauchte 412 s und lag damit knapp unter dem Zeitlimit. `unc-heretic` war im Einzellauf
  am langsamsten und ist in der Wiederholung am gleichmäßigsten.
- **Die Streuung ist größer als der Abstand zwischen den Modellen.** Dieselbe Aufgabe dauerte mit
  demselben Modell zwischen 122 s und 412 s. Vier Durchgänge reichen deshalb nur für eine grobe
  Aussage: `unc-coletti` und `unc-heretic` liegen etwa gleichauf, `unc-blackfrost` eher dahinter.
- Das Token-Tempo ist weiter bei allen gleich (58 bis 62 Tok./s in diesem Lauf).

Nicht getestet: `ajgazin/Swift-Qwen3.8-27B-Uncensored-Dynamic-MTP-GGUF` (15 % Ablehnungen,
Lizenz mit Umsatzgrenze) und `cyjin-yl/...-Cyber-agentic` (auf Offensive Security spezialisiert,
nur IQ4_XS, laut Karte auf eine eigene Laufzeit zugeschnitten).

## Erkenntnisse

### 32k Kontext reichen für Claude Code nicht

Mit 32k scheiterten fast alle Modelle, die mit 64k bestehen:

| Modell | 32k | 64k |
|---|---|---|
| `local-coder` | 0 / 3, alle im Zeitlimit | 3 / 3 |
| `qwen3-coder:30b` | 0 / 3 | 3 / 3 |
| `qwen3.8:27b` | 3 / 3, aber 282 bis 376 s | 3 / 3, 41 bis 142 s |

Claude Code belegt mit Systemprompt und Tool-Beschreibungen einen großen Teil des Kontexts. Bei
32k läuft der Rest nach wenigen Runden voll, Claude Code komprimiert ständig („Autocompact is
thrashing“) oder bricht ab. `qwen3-coder:30b` antwortete mit 32k in der bugfix-Aufgabe, es könne
wegen „Einschränkungen“ keinen Code bearbeiten, vermutlich weil Teile des Prompts verloren
gingen. **Mindestens 64k einstellen.** Mehr als 64k brachte in diesem Lauf nichts
(`devstral-small-2` mit 96k, `mimo-v2.6` mit 128k).

### Ausgeschieden

| Modell | Ergebnis | Grund |
|---|---|---|
| `deepseek-r1:32b` | 0 / 3 | Kann keine Tools aufrufen, hat also keinen Zugriff auf Dateien. Mit 64k außerdem nur zu 83 % auf der GPU und 8 Tok./s langsam. |
| `qwen3:8b` | 0 / 3 | Schnell (140 Tok./s), aber zu schwach. Die Fehlersuche endete im Komprimierungs-Kreislauf. |
| `devstral-small-2:24b` | 1 / 3 | Gab in der bugfix-Aufgabe den Tool-Aufruf als Text aus (`Bash{"command": ...}`) statt ihn auszuführen, damit endete die Sitzung nach einer Runde. Das Tool-Format passt nicht zuverlässig zu Claude Code über Ollama. |
| `mimo-v2.6:9b-q8_0` | 2 / 3 | Nah dran, aber mit echten Fehlern (multifile: Zwischensumme statt Endsumme ausgegeben). Für ein 9B-Modell beachtlich, als Standard zu unzuverlässig. |
| `flint:40b` | - | Nicht installiert, nicht gemessen. |

### Tempo

- `qwen3-coder:30b` ist ein Mixture-of-Experts-Modell: 30 Mrd. Parameter, davon pro Token nur ein
  kleiner Teil aktiv. Daher 140 Tok./s bei ähnlichem VRAM-Bedarf wie die 27B-Modelle (21,2 GB mit 64k).
- `qwen3.8:27b` ist mit 56 Tok./s mehr als doppelt so schnell wie die unzensierte Variante
  (25 Tok./s), obwohl beide auf demselben Basismodell beruhen. Die Datei ist kleiner (16,5 GB
  statt 18,5 GB), also vermutlich anders quantisiert. Die genaue Ursache ist nicht geprüft.
- Der Wert 14,6 Tok./s für `qwen3.8:27b` mit 32k ist ein Ausreißer. Die Denk-Messung im selben
  Lauf ergibt etwa 49 Tok./s.
- Ladezeiten sind keine Eigenschaft der Modelle: Die erste Kombination eines Modells lud von der
  Platte (34 bis 56 s), die zweite aus dem Datei-Cache von Windows (4 bis 10 s).

### Rohwert „Tool-Calls“ nicht überbewerten

`mimo-v2.6` fiel im einfachen Tool-Test durch (`FEHLER` in den Rohwerten), arbeitete in den
Agenten-Aufgaben über Claude Code aber mit Tools. Aussagekräftig sind die Agenten-Aufgaben.

## Nächste Schritte

- `local-qwen38` auf den fünf neuen Aufgaben messen, falls es wieder in Frage kommt.
- Mehr Kontext (E2) und Hinweise zu PowerShell 5.1 (erledigt, siehe oben) an `longcontext` und `psscript`
  messen: [roadmap.md](roadmap.md).
- Ablehnungsrate der unzensierten Modelle selbst prüfen statt der Modellkarte zu glauben.
- Die Änderungen einzeln messen (GPU-Aufteilung, Arbeitsregeln, Denkaufwand, MTP-Länge),
  jeweils als eigener Lauf mit `-Label`. Vorgehen: [erweitern.md](erweitern.md).

# Protokoll

Neue Einträge oben anfügen. Messwerte aus `scripts\Test-Model.ps1` stehen zusätzlich in
`logs\model-tests.log`.

## 2026-11-17 abends: Planer – Verteilung auf Karten und Hauptspeicher berechnen

Wunsch des Nutzers: Das Programm soll bei der Installation die Ausstattung des Rechners
ansehen und mathematisch berechnen, wie es die Modelle am besten auf die Ressourcen
verteilt. Gebaut im Arbeitsordner `Unzensiert-planer` (Zweig `planer`).

### Durchgeführt

1. **Rechnung** (`scripts\lib\Planner.ps1`, Beschreibung [planer.md](planer.md)):
   Speicher je Gerät aus `llama-fit-params --fit-print on` (Schätzung von llama.cpp für eine
   gegebene Verteilung) plus Reserve, MTP-Zuschlag und Bild-Encoder; Zeit je Token =
   Σ gelesene MiB × µs/MiB je Gerät; µs/MiB aus einer Kalibrierung mit `llama-bench` (Lauf nur
   auf dem Prozessor, je Karte ein Lauf „diese Karte zuerst“, lineares Gleichungssystem).
   Suche je Kontextgröße: schnellste Karte zuerst füllen und zuletzt in `--device` stellen
   (Ausgabe- und MTP-Schicht dorthin), bei MoE zuerst Experten auslagern (`--n-cpu-moe`),
   Bild-Encoder dahin, wo Platz bleibt, sonst Prozessor. Gewählt: größter Kontext ab 64k
   mit höchstens 15 % weniger Tempo als der schnellste.
2. **`scripts\Plan-Models.ps1`** (`-Model`, `-Recalibrate`, `-Verify`, `-Show`): schreibt
   die Optionen in `config\machine.json` (`fit: off`, `gpu-layers`, `device`,
   `tensor-split`, `n-cpu-moe`, `mmproj-device`/`mmproj-offload`, `ctx-size`), dazu
   `plans` und `calibration`. `-Verify` lädt und testet; lädt ein Modell nicht oder
   stürzt es unter einer Anfrage ab (Fehler 500), plant es mit 1 GB mehr Reserve neu.
   Kartenwerte eines MoE-Modells übernimmt es aus der Kalibrierung eines dichten Modells.
3. **`config\planner.json`**: Reserve 1024 MiB je Karte, MTP-Zuschlag 1408 MiB,
   Hauptspeicher-Reserve 6 GB, Kontextgrößen 128k/96k/64k/32k, `minCtx` 64k,
   Toleranz 15 %.
4. **Installer**: nach dem Download `Plan-Models.ps1 -Model <modell> -Verify`; scheitert
   das, nimmt `Clear-ModelPlan` die Optionen wieder heraus (llama.cpp verteilt selbst).
5. **`Measure-Setup.ps1 -Planned`**: Planer für genau die sichtbar gemachten Karten.
6. **Tests**: `Test-Install.ps1` +15 Prüfungen mit einem nachgebildeten Speichermodell
   (Reihenfolge, volle schnelle Karte, Kontextwahl, Experten, Bild-Encoder, Lösen der
   Kalibrierung, unplausible Kalibrierung); `Test-Setup.ps1` prüft `planner.json` und
   dass `llama-fit-params.exe` und `llama-bench.exe` da sind.

### Gemessen

- Kalibrierung auf beiden Karten (`local-coder`): RTX 5070 Ti 1,38 µs/MiB (≈ 760 GB/s),
  RTX 3060 3,57 µs/MiB (≈ 294 GB/s), Hauptspeicher 19,9 µs/MiB. Verhältnis der Karten 2,6,
  Herstellerangaben 2,5. Drei Aufteilungen von Hand (70/30, 55/45, 45/55: 31,5 / 27,3 /
  25,1 Tok./s mit `llama-bench`) ergeben dieselbe Differenz (2,16 und 2,10 µs je MiB).
- Zusatzspeicher, den die Schätzung nicht kennt (Aufteilung 30/36, ohne Grenze): erste
  Karte +650 MiB (CUDA-Kontext), letzte Karte +2025 MiB (davon ≈ 1375 MiB MTP-Entwurf).
  Die RTX 5070 Ti hat eine feste Grenze bei 15,58 GB; darüber lagert der Treiber still aus
  (Sysmem Fallback). Die Handeinstellung 70/30 stand auf das MiB an dieser Grenze.
- **Absturz mit 512 MiB Reserve**: Nach dem Start misst der Router die anderen Modelle mit
  eigenen Prozessen (`measure_next`, je ≈ 550 MiB CUDA-Kontext); in diesem Moment starb
  `local-coder` (Status -1073741819). Daher Reserve 1024 MiB.
- Ergebnisse (`Test-Model.ps1`, Tempo mit MTP; Tool-Calls und Bilder überall OK):

  | Karten | Modell, Kontext | `--fit` | Hand 70/30 | Planer |
  |---|---|---|---|---|
  | beide | `local-coder`, 128k | 44 | 58,5 / 61,8 | 65,7 / 70,7 (37 + 29 Einheiten) |
  | RTX 5070 Ti allein | `local-coder`, 64k | 20,9 | | 21,8 |
  | RTX 5070 Ti allein | `local-fast`, 64k | 97,1 | | 105,7 |
  | RTX 3060 allein | `local-fast`, 64k | 62,2 | | 65,0 |

  Freie Wahl des Planers: RTX 5070 Ti allein `local-coder` 96k mit 18,7 Tok./s; RTX 3060
  allein `local-fast` 128k mit 58,2; RTX 3060 mit 4 GB frei 128k mit 53,6. Die
  Handeinstellung mit umgekehrter Reihenfolge lud nicht (zu voll).
- Kalibrierung mit MoE-Modell unzuverlässig: RTX 3060 0,55 µs/MiB (unmöglich), RTX 5070 Ti
  unplausibel (Ersatzwert). Für eine Karte ohne Folgen, bei mehreren Karten übernimmt der
  Planer die Werte eines dichten Modells.
- Ohne Modell: `Test-Setup`, `Test-Install`, `Test-Guard` (91), `Test-Templates`,
  `Test-Tasks` bestanden.
- **Angewendet auf den Entwicklungsrechner** (`Plan-Models.ps1 -Verify`, alle drei
  Agenten-Modelle, Handeinstellung gesichert in `<installRoot>\run\machine.json.vor-planer`):
  `local-coder` 128k 66,9 Tok./s, `local-qwen38` 128k 70,5, `local-fast` erst 64k mit
  200,8. Folgefehler bemerkt: `claude-local` nimmt das kleinste Fenster der `/model`-Auswahl,
  jede Sitzung wäre auf 64k geschrumpft. Korrektur: Standardmodell zuerst planen, die
  anderen Modelle der Auswahl bekommen mindestens dessen Kontext. Danach `local-fast` 128k
  mit 171,2 Tok./s (vorher von Hand 83 bis 140), Experten einer Schicht im Hauptspeicher.
  Vorhergesagt waren für 128k 32 % weniger als für 64k, gemessen etwa 15 %: Die Rechnung
  ist bei ausgelagerten Experten zu pessimistisch.

### Offen

- Echte Rechner mit anderen Karten, AMD/Intel, mehr als zwei Karten: ungeprüft.
- Ob ein Plan auslagert, prüft `-Verify` nicht (nur, ob er läuft).
- Die Formel berücksichtigt keine Kontext-Tiefe; ob `local-coder` mit dem Plan im
  Benchmark so zuverlässig bleibt, ist nicht gemessen (nur `Test-Model.ps1`).

## 2026-11-17: Installer für jeden Windows-Rechner

Ziel des Nutzers: Jeder soll das Projekt herunterladen, installieren und nutzen können, so
einfach wie möglich. Entscheidungen des Nutzers: NVIDIA als erprobter Weg, AMD und Intel
experimentell über Vulkan; Installer und Schnellstart auf Englisch, Doku weiter deutsch;
Start per Einzeiler und per ZIP mit Doppelklick. Gebaut in einem eigenen Arbeitsordner
(`git worktree`, Zweig `installer`), weil parallel ein Benchmark aus dem Projektordner lief.

### Durchgeführt

1. **Projekt und Rechner getrennt.** Neue Datei `config\machine.json` (nicht im
   Repository) mit den Werten dieses Rechners; `lib\Config.ps1` legt ihre Abschnitte über
   die Dateien in `config\` (`Read-Config`, `Merge-ConfigObject`, `null` entfernt einen
   Schlüssel). Aus den gemeinsamen Dateien entfernt und nach `machine.json` verschoben:
   `installRoot` `E:\LlamaCpp`, `projectsRoot` `E:\Projekte`, `package`, `gpu-layers 999`,
   alle `tensor-split`, `mmproj-device` und `device`, die Q4_K_M-Datei des
   Autocomplete-Modells. Neue Standardwerte: `%LOCALAPPDATA%\claude-local`,
   `%USERPROFILE%\Projects`, `modelsDir` und `workDir` leer = unter `installRoot`.
   Ohne Angaben zur Aufteilung verteilt llama.cpp selbst (`--fit`, voreingestellt).
2. **Wächter ohne feste Laufwerke.** `config\guard.json` nennt `%CLAUDE_LOCAL_ROOT%` und
   `%CLAUDE_LOCAL_PROJECTS%`; `scripts\_common.ps1` setzt beide, die Hooks lesen sie über
   `scripts\hooks\HookEnvironment.ps1` (beim Start von Hand aus den Einstellungen).
   `machine.json` ist zusätzlich geschützt. `Test-Guard.ps1` setzt feste Beispielordner aus
   `tests\guard-cases.json` (`machine`), `{repo}` steht für das Repository: 91 Fälle.
3. **Downloads mit Quelle.** Jedes Profil in `config\models.json` hat `role` und
   `download` (Hugging-Face-Repository, fester Commit, Größe, SHA-256 je Datei), erzeugt
   aus den Antworten der API, nicht abgeschrieben. `scripts\Get-Model.ps1` lädt fortsetzbar
   über `<name>.part` und benennt erst nach Größe und Prüfsumme um (`lib\Download.ps1`).
   Neue Rechner bekommen das Autocomplete-Modell als Q8_0 von `ggml-org`.
4. **Hardware erkennen.** `lib\Machine.ps1`: Grafikkarten (`nvidia-smi`, Adapter von
   Windows, Geräteliste von llama.cpp ohne integrierte Grafik), Hauptspeicher, freier
   Platz, Git Bash, Claude Code. `config\setups.json`: Stufen nach Grafikspeicher.
   `Install-LlamaCpp.ps1` wählt mit `package: auto` das Paket nach Karte (`packages` in
   `server.json`), prüft mit `--list-devices` und weicht aus (CUDA 13.5, CUDA 12.4, Vulkan);
   vor dem Entpacken leert es den Programmordner (nur `b<Nummer>`), damit kein zweites
   Backend lädt, und stoppt einen laufenden Server.
5. **Installer.** `scripts\Install.ps1` (sieben Schritte, fragt vor jeder Installation und
   jedem Download, `-Plan`, `-Yes`, `-InstallRoot`, `-Model`), `Install.cmd` zum
   Doppelklicken, `install.ps1` als Einzeiler (Git-Klon oder ZIP nach
   `%LOCALAPPDATA%\Programs\claude-local`, ohne `exit`), `scripts\Uninstall.ps1` mit
   `Uninstall.cmd` (löscht nur, was der Installer angelegt hat). Fragen und
   Schrittanzeige in `lib\Dialog.ps1`.
6. **Agent auf fremden Rechnern.** `claude-local` findet Claude Code auch ohne
   aktualisierten PATH, startet mit dem ersten geladenen Modell, wenn das Standardmodell
   fehlt, zeigt in `/model` nur geladene Modelle und ersetzt ohne Git Bash `Bash` durch
   `PowerShell`. Der zweite Blick prüft mit dem Standardmodell, wenn `local-qwen38` fehlt.
   `Test-Model.ps1 -NoLog` schreibt nicht in das Log im Repository (sonst blockiert es
   ein späteres `git pull`) und endet mit Code 1 bei `FAILED`; `Get-GpuMemory` ohne
   `nvidia-smi` liefert `n/a`.
7. **Tests.** Neu `scripts\Test-Install.ps1` (43 Prüfungen ohne Download und Modell:
   `machine.json`, Geräteliste, Stufenwahl, Werkzeuge, Download-Einträge, Probelauf
   `Install.ps1 -Plan` für einen leeren Rechner, Einzeiler ohne `exit`). `Test-Setup.ps1`
   meldet nicht geladene Profile als Hinweis statt als Fehler, prüft die Download-Einträge
   gegen die Dateien jedes Profils und `setups.json`. `.gitattributes`: `.cmd` mit CRLF.
8. **Doku.** README mit englischem Schnellstart; `einrichtung.md` beschreibt Installer,
   Stufen, `machine.json`, Aktualisieren und Deinstallieren; angepasst `architektur.md`,
   `backend.md`, `modelle.md`, `agent.md`, `sicherheit.md`, `projekte.md`,
   `erweitern.md`, `CLAUDE.md` (Regeln: Projekt und Rechner getrennt, Repository
   öffentlich, `Test-Install.ps1`).

### Gemessen und geprüft

- Ohne Modell: `Test-Setup`, `Test-Install` (43), `Test-Guard` (91), `Test-Templates`,
  `Test-Tasks` bestanden. `Install.ps1 -Plan` auf diesem Rechner übernimmt `E:\LlamaCpp`,
  erkennt beide Karten (28562 MiB) und die vorhandenen Modelldateien; für einen leeren
  Rechner schlägt es `E:\claude-local` und `local-coder` (16,9 GB) vor.
- Herkunft der Bild-Encoder: SHA-256 der drei `mmproj`-Dateien nachgerechnet, stimmt mit
  Hugging Face überein. Damit ist der offene Punkt „Quelle und Prüfsummen der
  `mmproj`-Dateien“ erledigt. Alle Modelldateien sind byte-gleich groß wie die Quellen.
- Claude Code ohne Anmeldung: mit leerem Konfigurationsordner (`CLAUDE_CONFIG_DIR`) und
  einem Stub-Server als `ANTHROPIC_BASE_URL` antwortet `claude -p` sofort, ohne
  Login-Abfrage (Claude Code 2.1.326). Die interaktive Ersteinrichtung (Farbthema,
  Vertrauen) ist so nicht prüfbar.
- **Hardware-Stufen** mit dem neuen `scripts\Measure-Setup.ps1` (nur gewählte Karten
  sichtbar, allgemeine Einstellungen ohne Feinabstimmung, `Test-Model.ps1` plus
  Prompt-Tempo mit 26.177 Tokens). Alle Läufe: Tool-Calls OK, Bild-Eingabe OK.

  | Nachgestellt | Profil, Kontext | Antwort | Prompt | Sitzungsbeginn |
  |---|---|---|---|---|
  | beide Karten (28 GB), ohne Feinabstimmung | `local-coder`, 128k | 44,4 Tok./s | 815 Tok./s | 32 s |
  | beide Karten, je 2560 MiB frei (≈ 23 GB) | `local-coder`, 64k | 49,4 Tok./s | 882 Tok./s | 30 s |
  | RTX 5070 Ti allein (16 GB) | `local-coder`, 64k | 20,9 Tok./s | 572 Tok./s | 46 s |
  | RTX 5070 Ti allein (16 GB) | `local-fast`, 64k | 97,1 Tok./s | 775 Tok./s | 34 s |
  | RTX 3060 allein (12 GB) | `local-coder`, 64k | 10,8 Tok./s | 184 Tok./s | 143 s |
  | RTX 3060 allein (12 GB) | `local-fast`, 64k | 62,2 Tok./s | 244 Tok./s | 107 s |
  | RTX 3060, 4096 MiB frei (≈ 8 GB) | `local-fast`, 32k / 64k | 55,8 / 56,8 Tok./s | 211 / 207 Tok./s | 124 / 126 s |
  | keine Karte (Core i9-14900K) | `local-fast`, 32k | 25,9 Tok./s | 74 Tok./s | 354 s |

  Folgen für `config\setups.json`: 16 GB bekommt `local-coder` (zuverlässiger, 21 Tok./s),
  `local-fast` als genannte Alternative; 12 GB bekommt `local-fast`; 8 GB bekommt 64k
  statt 32k Kontext, weil es gleich schnell läuft. Ohne Feinabstimmung ist `local-coder`
  auf beiden Karten ein Viertel langsamer als mit der eigenen Aufteilung (44 statt etwa
  60 Tok./s); die Feinabstimmung bleibt in `machine.json` dieses Rechners. Der private
  Speicher des Modellprozesses lag bei Auslagerung zwischen 10,4 und 19,5 GB; bei voller
  Karte zeigt Windows auf diesem Rechner keinen verlässlichen Wert.
- **Ende-zu-Ende auf diesem Rechner:** `Install.ps1 -Yes` aus dem Projektordner (Reparatur):
  übernimmt Ordner, Paket und Feinabstimmung, lädt nichts, `Test-Setup` bestanden,
  `local-coder` 61,8 Tok./s, Tool-Calls und Bild-Eingabe OK.
- **Fehler gefunden und behoben (Abschlussprüfung):** Ein Lauf `claude-local -p` im
  Repository hing über 4 min in einer Schleife. Ursache: Claude Code 2.1.326 schreibt die
  Beschreibungen der Werkzeuge (`{"name":"Edit","description":...}`) und bei jeder Anfrage
  die bisherigen Nachrichten in den Verlauf. `Check-Stop.ps1` zählte jedes `"name":"Edit"`
  als Schreibaufruf, meldete nach reinem Lesen „Du hast Dateien geändert“, und das Modell
  wollte daraufhin Dateien nachbessern, was `-p` ohne Freigabe ablehnte, immer wieder.
  Jetzt zählen nur `tool_use`-Blöcke, jede Aufruf-ID einmal; zwei neue Fälle in
  `Test-Setup.ps1`. Gegenprobe in einem Testordner: vorher 3 Runden mit falscher
  Erinnerung, nachher 2 Runden, 7 s. Ungeklärt, seit welcher Version von Claude Code das
  so ist: Benchmark-Zeiten der letzten Läufe können unnötige Erinnerungsrunden enthalten.

### Offen

- Nicht prüfbar auf diesem Rechner: ein frischer Windows-Rechner (Erststart von Claude Code
  interaktiv, `winget` für Git, Paketwahl bei altem Treiber), AMD und Intel über Vulkan,
  der Agent mit dem Werkzeug `PowerShell` statt `Bash`, eine echte 24-GB- oder 8-GB-Karte.
  Ein zweiter Rechner (Bekannte, Rückmeldungen über GitHub-Issues) wäre der nächste Test.
- Die Qualität der Stufen ist nur über `Test-Model.ps1` geprüft, nicht im Benchmark:
  Läuft `local-coder` mit 64k statt 128k Kontext genauso zuverlässig?

## 2026-11-17: „Ausbruch“ detaillierter und an mehr Stellen

### Durchgeführt

1. **Bild aus Zeichen mit Einzelheiten** (`lib\CharArt.ps1`): Licht von oben (oben
   heller, unten dunkler), Schatten rechts unten aus `:;.`, Farbnasen von den
   Unterkanten (`|!:` mit Tropfen), Funken `✦ ✧ * +`. Das Bild ist jetzt 10 statt 7 Zeilen
   hoch. Aufgeteilt in `Get-CharArtCells` (Raster), `Format-ArtCells` (Terminal) und
   `Save-ArtCellsImage` (PNG).
2. **Wand aus Zeichen** hinter dem Terminal: `New-CharWall` zeichnet rechts unten FREI und
   darum gesprühte Zeichen; `Install-Style.ps1` speichert sie als `wand.png` und trägt sie
   als Hintergrundbild des Profils ein (20 % Deckkraft, `terminal.wall`).
3. **Mehr Stellen im Stil:** Sprühlinie unter jedem Bild, ein Spruch bei jeder neuen Shell
   (`texts.sprueche`), gesprühte Trennzeichen und davonfliegende Zeichen am Ende jeder
   Eingabe- und Statuszeile (`trail`), Bild WOLKE in Cyan vor `claude`, Abschied mit
   Sitzungsdauer nach `claude-local` (`Get-LocalLookFarewell`), acht weitere Wartetexte.
4. **`Test-Setup.ps1`:** Wolke-Bild bleibt einfarbig (Gegenprobe: bunt → 190 Zellen
   außerhalb), Sprühlinie und Spur in verlangter Breite, Größe der Wand.

### Gemessen

Bild UNZENSIERT beim ersten Zeichnen etwa 240 ms (vorher 145 ms), danach etwa 75 ms;
FREI etwa 35 ms; Wand etwa 310 ms beim Installieren. Nicht geprüft: Wirkung im echten
Fenster.

## 2026-11-17: Neues Erscheinungsbild „Ausbruch“

### Durchgeführt

1. **Zweiter Stil „Ausbruch“** (`config\styles\ausbruch.json`): bunt, frei, rebellisch.
   Bilder aus farbigen Buchstaben und Zeichen statt aus Pixeln: über der Shell das Wort
   UNZENSIERT, vor jeder Sitzung von `claude-local` das Wort FREI, gesetzt in einer
   Blockschrift, gefüllt mit zufälligen Zeichen, durch einen Farbkreis aus sieben Farben
   gefärbt; Sprühnebel um die Buchstaben, rechts brechen Zeichen aus und fliegen davon.
   Stimmungen: Straße (Shell), Frei (lokal, ganzer Farbkreis), Wolke (Cloud, nur Cyan).
   Gesprühte Messlinien, bunter Ordnername, wechselndes Eingabezeichen, eigene Themen für
   Claude Code, rebellische Wartetexte, Farbrad als Tab-Symbol ([stil.md](stil.md)).
2. **Stile umschaltbar:** `config\style.json` wählt nur noch den Stil (`active`) und hält,
   was alle teilen (Profil-GUID, Variable `CLAUDE_LOCAL_LOOK` statt `NACHTSCHICHT_MODE`,
   Endung der Sicherungen). Der bisherige Inhalt liegt als
   `config\styles\nachtschicht.json` daneben, mit `shell.mode`.
   `Install-Style.ps1` nimmt die Einträge aller Stile heraus, bevor es den aktiven
   schreibt.
3. **Neu `scripts\lib\CharArt.ps1`** (Bilder aus Zeichen); `lib\Style.ps1` mit Farbkreis,
   gesprühten Messlinien und `Get-ShellModeName` statt fest `werkbank`.
4. **Statuszeile:** liest stdin auch mit vorangestelltem BOM (vorher leere Zeile ohne
   Modell und Kontext, wenn ein Aufrufer eines mitschickte).
5. **`Test-Setup.ps1`** prüft Stil-Dateien, Blockschrift, Bildbreite, Messlinien und die
   Statuszeile.
6. „Ausbruch“ ist installiert und aktiv; ein zweiter Lauf von `Install-Style.ps1` ändert
   nichts.

### Gemessen

Bild UNZENSIERT beim ersten Zeichnen etwa 145 ms, danach etwa 50 ms; Bild FREI etwa
23 ms; Statuszeile lokal etwa 480 ms. Nicht geprüft: das Aussehen im echten Fenster.

## 2026-11-17: Zweiter Blick im Benchmark, erster Teil (Lauf `h3-qwen38`)

### Durchgeführt

1. **Benchmark für den zweiten Blick:** `-ReviewModel` wählt den Prüfer für einen Lauf,
   `-ExtraSeconds` verlängert jedes Zeitlimit um die Prüfung, jeder Lauf vermerkt seine
   Prüfungen aus `review.log`. Während des Laufs geht der Rechner nicht in den Ruhezustand.
   Probelauf `h3-probe`: `datenblatt` bestanden, ein zweiter Blick, 67 s, kein Befund.
2. **Geplant:** `local-coder` an sieben Aufgaben (`extend`, `refactor`, `psscript`,
   `screenshot`, `longcontext`, `datenblatt`, `pinwechsel`), je dreimal, mit `-Git`
   und `-ExtraSeconds 300`. Einmal prüft `local-qwen38` (`h3-qwen38`), einmal
   `local-coder` (`h3-coder`).
3. **Abgebrochen nach 9 von 42 Läufen:** Um 17:07 Uhr stellte eine parallele Sitzung das
   Erscheinungsbild um (`config\style.json`, `scripts\lib\Style.ps1`). Danach brach
   `claude-local` sofort ab (`Set-Item` in `Style.ps1:175`, `modeVariable` leer). Der
   Benchmark prüfte trotzdem die unveränderten Aufgabendateien und trug 33 Läufe mit 0 s
   als „nicht bestanden“ ein. Diese 33 Läufe habe ich aus `results.jsonl` entfernt; der
   Datensatz `h3-qwen38` enthält nur die 9 echten Läufe und im Feld `error` den Grund.
   `h3-coder` ist nicht gelaufen.
4. **Absicherung:** Endet `claude-local` ohne Ergebniszeile, bricht `Benchmark-Models.ps1`
   jetzt mit Exit-Code 1 ab. Die Läufe davor bleiben im Datensatz, der Grund steht im
   Feld `error`.

### Ergebnis der 9 gültigen Läufe (Prüfer `local-qwen38`)

| Aufgabe | bestanden | Zeit mit zweitem Blick | `b12433` ohne | Prüfungen | Befunde |
|---|---|---|---|---|---|
| `extend` | 3 / 3 | 1102 s | 886 s | 3, je 50 bis 144 s | 1 FEHLER, 1 Hinweis |
| `refactor` | 3 / 3 | 1290 s | 799 s | 3, je 98 bis 134 s | 5 Hinweise |
| `psscript` | 2 / 3 | 2056 s | 1221 s | 3, je 142 bis 165 s | 1 Hinweis |
| zusammen | 8 / 9 | 4448 s | 2906 s | 9, im Mittel 126 s | 1 FEHLER, 7 Hinweise |

- **Der eine FEHLER war ein echter Treffer:** In `extend #2` hieß ein neuer Test
  `add_to_default_warehouse` ohne `test_` und lief nie. Der Agent hat den Befund
  nachgeprüft, bestätigt und behoben (37 statt 36 Tests). Die Prüfung der Aufgabe hätte
  das nicht bemerkt; der Lauf bestand schon vorher.
- **Kein Fehlalarm:** Keine FEHLER-Meldung, die nicht stimmte. Die 7 Hinweise gingen nur
  an den Nutzer und hielten den Agenten nicht auf.
- **Ein Fehler übersehen:** `psscript #3` fiel durch (ungültiges `-Since` mit `-Format json`
  endet mit Exit-Code 1 statt 2). Der Prüfer meldete nichts.
- **Kosten:** 53 % mehr Zeit für diese drei Aufgaben. Davon entfallen etwa 1130 s auf die
  neun Prüfungen selbst (einschließlich Wechsel der Modelle). Die übrigen etwa 410 s sind
  nicht zugeordnet: Streuung der Läufe oder die Git-Repositories (nicht getrennt gemessen).
- **Grenzen:** 9 Läufe, ein Prüfer, nur Aufgaben ohne Bezug zu Fakten. Ob `local-coder`
  als Prüfer mehr findet und ob der zweite Blick bei `datenblatt` und `pinwechsel` hilft,
  ist offen. Die Wahl des Prüfers bleibt bis zur vollständigen Messung bei
  `local-qwen38`.

## 2026-11-17: Erste öffentliche Version

### Durchgeführt

1. Das Repository ist öffentlich und beginnt mit einer neuen Git-Geschichte. Die
   bisherigen 23 Commits liegen in einem privaten Archiv.
2. Lizenz MIT (`LICENSE`), Abschnitt „Lizenz“ in der README.
3. Vorher durchsucht: keine Schlüssel oder Passwörter in Dateien und Geschichte, Commits
   nur mit der anonymen GitHub-Adresse. Persönliche Pfade im Protokoll durch
   `%USERPROFILE%` ersetzt.
4. Verweise auf Commit `fbb8c80` (Stand vor dem Umbau auf llama.cpp) betreffen die
   Geschichte vor der öffentlichen Version; sie ist nicht veröffentlicht.

## 2026-11-17: Härtung H4 – Benchmark-Aufgaben für Faktentreue und Konsistenz

### Durchgeführt

1. **`datenblatt`:** Treiber für den erfundenen Sensor HX-7 nach
   `docs/datenblatt-hx7.md`. Daneben liegen der Treiber und das Datenblatt des HX-5, und
   das HX-7-Datenblatt nennt ihn „pinkompatibel“. Unterschiede: Adresse 0x3A statt 0x44,
   Messung erst auf Befehl, Statusbits DRDY und ERR, niederwertiges Byte zuerst, andere
   Formel, Sättigung bei 100 %. Die Prüfung simuliert den Sensor genau nach Datenblatt.
2. **`pinwechsel`:** Pumpe von GPIO17 auf GPIO23 (Pin 16), Regensensor mit offenem
   Kollektor auf GPIO17 (Pin 11, braucht Pull-up), bei Regen nicht gießen. Die Prüfung
   verlangt alle Stellen stimmig: `config/pins.json`, `DEFAULT_PINS`, README,
   Verdrahtungsplan mit Stiftleisten-Pin, `facts.json` und `check_facts.py`, eigene Tests.
   Das Projekt bringt Prüfbefehl und Faktenabgleich mit.
3. **Regel `fakten`** in `benchmark\lib\rulecheck.py` und im Bericht: neuer Fakt mit
   Quelle in `facts/facts.json`.
4. **`check_facts.py`** erkennt zusätzlich Schlüssel in Anführungszeichen in jeder Datei
   (`"pumpe": 17` in einem Python-Dict) und Tabellenzeilen mit genau einem Pin und genau
   einem bekannten Label (`| Pumpe (Relais IN1) | GPIO17 | 11 |`).
5. **`Test-Tasks.ps1`** prüft, dass Kopien von `check_facts.py` und `Check.ps1` in
   Aufgaben der Fassung der Vorlage entsprechen.

### Gemessen (ohne Modell)

- `Test-Tasks.ps1`: beide Aufgaben fallen im Ausgangszustand durch, die Musterlösung
  besteht mit allen fünf Regeln; auch mit `-Overlay projekt`.
- Typische Fehlversuche fallen durch. `datenblatt`: HX-5 abgeschrieben, Byte-Reihenfolge
  falsch, ERR nicht beachtet. `pinwechsel`: README nicht angepasst, Rückfallwert im Code
  vergessen, falscher Stiftleisten-Pin im Plan, Pull-up vergessen. Die ersten beiden von
  `pinwechsel` meldet auch `check_facts.py`, also die Abschlussprüfung.
- `check_facts.py` an der HackMD-Kopie: weiter alle eingebauten Fehler gefunden, keine
  neuen Fehlalarme; ein Tabellenfehler (IR-LED auf GPIO26) wird jetzt erkannt.
- `Test-Setup.ps1`, `Test-Templates.ps1`, `Test-Tasks.ps1` bestanden.

### Gemessen mit Modell (Lauf `h4`, `local-coder`, je dreimal, ohne zweiten Blick)

| Aufgabe | Bestanden | Zeiten | Regeln |
|---|---|---|---|
| `datenblatt` | 3 / 3 | 129, 198, 121 s | 12 / 15 |
| `pinwechsel` | 3 / 3 | 103, 105, 130 s | 15 / 15 |

- `fakten` 6 / 6: In jedem Lauf trug das Modell die neuen Fakten mit Quelle ein. Bei
  `datenblatt` waren es sieben HX-7-Fakten mit Abschnittsangabe, ohne dass der Auftrag
  das verlangte.
- Die drei Verstöße gegen `nodeadcode` (alle bei `datenblatt`) waren Fehlalarme. Es
  handelte sich um Rechenkommentare in Tests wie `# raw_t = 18304 -> T = 18304/256 - 50 = 21.5`.
  Einer enthielt einen liegengebliebenen Denkrest („wait let me use a bigger value“).
  Danach verschärft: In Python zählt eine Kommentarzeile nur als Code, wenn sie sich als
  Python übersetzen lässt. Mit der neuen Prüfung sind alle drei Läufe sauber. Im
  gespeicherten Ergebnis von `h4` steht der alte Wert.
- **Bewertung:** Beide Fehlerklassen aus der echten Arbeit zeigt `local-coder` an diesen
  Aufgaben nicht, wenn Datenblatt und Faktenablage im Projekt liegen. Die Aufgaben sind
  kleiner als die echte Firmware (2 Geräte, über 20 Dateien). Damit ist offen, ob der
  Unterschied an der Größe oder an Faktenablage und Regel liegt. Ein Vergleichslauf ohne
  `facts\` und ohne die Regel fehlt.

### Danach

- **Schalter `-Git` für `Benchmark-Models.ps1`:** Arbeitsordner werden Git-Repositories
  mit den Aufgabendateien als erstem Commit, damit der zweite Blick im Benchmark
  mitläuft ([erweitern.md](erweitern.md)).

## 2026-11-17: Härtung H3 – zweiter Blick durch ein zweites lokales Modell

### Durchgeführt

1. **`scripts\Invoke-Review.ps1`** mit den Bausteinen in `scripts\lib\Review.ps1`:
   nicht committete Änderung (Diff gegen `HEAD` und neue Dateien), Auftrag aus dem Verlauf
   der Sitzung, `CLAUDE.md`, `facts\facts.json` und die geänderten Dateien vollständig in
   einer Anfrage an `local-qwen38`. Antwortform `FEHLER | ...` und `HINWEIS | ...`.
   Prüfauftrag in `config\zweiter-blick.md`, Einstellungen unter `review` in
   `config\agent.json`, Protokoll `E:\LlamaCpp\logs\review.log`.
2. **Abschlussprüfung, Schritt 3:** einmal je Antwort, wenn Prüfbefehl und Erinnerung nichts
   mehr offen haben, auch wenn das Modell nach der Erinnerung nichts mehr ändert. Fehler
   gehen an das Modell zurück, reine Hinweise an den Nutzer. Das Zeitlimit des Hooks wächst
   um `timeoutSeconds` + 60 s.
3. **`Test-Setup.ps1`:** neun Fälle ohne Modell: Antwort zerlegen, Diff und neue Dateien
   zählen, kein Git, Auftrag aus dem Verlauf, Zeitlimit des Hooks.

### Gemessen

An einer Git-Kopie von `HackMD`, Änderung mit 20 Zeilen (IR-LED verlegt,
`ir_send_repeat` ergänzt) und fünf eingebauten Fehlern. Tabelle in
[agent.md](agent.md), Abschnitt „Zweiter Blick“. Kurz:

- `local-qwen38`, drei Läufe: Off-by-one, Widerspruch in der README und veraltete
  Kopfkommentare jedes Mal gefunden. Millisekunden statt Ticks und die erfundene Angabe
  „5V-tolerant“ nie gefunden. 33 bis 87 s.
- `local-coder` als Prüfer, zwei Läufe: dazu beide Male die Ticks, einmal die
  5V-Angabe. 76 bis 128 s.
- Fehlerfreie Fassung derselben Änderung: kein Befund in vier Läufen.
- Von Ende zu Ende über `Invoke-StopHook`: Halt 1 Erinnerung, Halt 2 zweiter Blick (53 s)
  mit dem Off-by-one-Fehler, Halt 3 Ende.
- `Test-Setup.ps1` bestanden.

### Fehler und Erkenntnisse

- **Windows PowerShell 5.1 und `git` auf stderr:** Mit `ErrorActionPreference = 'Stop'`
  wird schon die Warnung über Zeilenenden zum Abbruch, auch mit `2>$null`. In
  `Invoke-Git` gilt deshalb `Continue`.
- **Schwelle:** Die Teständerung mit echten Fehlern hatte 27 Zeilen (fehlerfreie Fassung).
  Die zuerst geplante Schwelle von 30 hätte sie übersprungen; jetzt 20 (Annahme).
- **Die erfundene 5V-Angabe fand `local-qwen38` in vier von vier Läufen nicht.** Gegen
  erfundene Fakten bleibt die Faktenablage mit Quelle (H1) das Netz; der zweite Blick
  fängt vor allem Logikfehler und Widersprüche.

### Offen

- Wahl des Prüfers (`local-qwen38` gegen `local-coder`) an mehreren Aufgaben messen (H4).
- Wie lange der Wechsel der Modelle in einer echten Sitzung dauert (Neuladen und neues
  Einlesen der Unterhaltung von `local-coder`), ist nicht gemessen.

## 2026-11-17: Härtung H1 und H2 – Fakten mit Quelle, Abgleich über Dateien

### Anlass

Härtungsprogramm aus der echten Arbeit am ESP32-Projekt `HackMD` ([roadmap.md](roadmap.md),
Abschnitt „Härtung“). Der Nutzer wählte für H3 die lokale Variante A.

### Durchgeführt

1. **`facts\facts.json` in jedem neuen Projekt** (Vorlage `gemeinsam\facts\`): Fakten
   mit `id`, `value`, `source` oder `"status": "annahme"`, bei Pins `device`,
   `direction`, `labels`; `code` nennt Namen in Code und Konfiguration, die den Wert
   tragen. Beschreibung `facts\README.md`.
2. **`scripts\check_facts.py`** als Schritt „Fakten“ im Prüfbefehl beider Vorlagen
   (PowerShell-Vorlage: optional, falls Python fehlt). Prüfungen: Quelle vorhanden, Werte
   im Code gleich (Zahlen als Zahlen, Pins in jeder Schreibweise), Pins in der Doku beim
   richtigen Signal, kein unbekannter Pin, kein Pin doppelt je Gerät, Platinenprofil.
   Ersetzt den ersten Entwurf vom 16.11. (nur Pins, ein Gerät).
3. **Platinenprofil `facts\boards\esp32.json`**, belegt aus der lokalen ESP-IDF 5.1
   (`soc_caps.h`: kein GPIO20, 24, 28 bis 31, GPIO34 bis 39 nur Eingang; `spi_pins.h`:
   GPIO6 bis 11 Flash) und dem Datenblatt (Strapping-Pins 0, 2, 5, 12, 15).
4. **Regel „Fakten belegen statt raten“** in `config\entwicklungsregeln.md` und in der
   `CLAUDE.md` beider Vorlagen.
5. **`Test-Templates.ps1`:** neue Dateien vorhanden; ein Widerspruch zu `facts.json` und
   ein Fakt ohne Quelle lassen den Prüfbefehl scheitern, nach der Korrektur besteht er.

### Gemessen

- An einer Kopie von `HackMD` mit 25 Fakten für zwei Geräte (Controller und
  ESP32-CAM-Agenten): Der Abgleich fand fünf in der Doku erwähnte Pins ohne Eintrag (Liste
  freier Pins in `wiring.html`, ADC-Kanäle in einem Kommentar), danach bestanden. Alle
  acht eingebauten Fehler gefunden: Pin in README und Header geändert, Puffergröße nur in
  einer der beiden Firmwares geändert, Flash-Pin, Ausgang auf Eingangs-Pin, nicht
  vorhandener Pin GPIO31, Fakt ohne Quelle, nicht erfasster Pin.
- Schreibweisen: Python mit Typangabe, PowerShell, JSON, C mit `GPIO_NUM_`, Hex gegen
  Dezimal, Spannung mit und ohne Einheit; `LED_PIN == 5` zählt nicht als Zuweisung.
- `Test-Templates.ps1` bestanden (beide Sprachen, je 21 Prüfungen).

### Offen

- Ob das Modell die Faktenablage von sich aus pflegt und die Regel befolgt: H4.
- `HackMD` selbst ist nicht nachgerüstet (nur die Kopie im Scratchpad).

## 2026-11-16 mittags: llama.cpp b12433 (G5), Vorbereitung Denkbudget (Q4)

### Durchgeführt

1. **Build-Wechsel b12359 → b12433** nach dem Verfahren in [backend.md](backend.md);
   `config\server.json`, `backend.md`, `architektur.md` und `README.md` angepasst.
2. **Vergleichsprofile für Q4:** `local-coder-rb2048`, `-rb512` und `-rb0` (gleiche Datei,
   `reasoning-budget` 2048, 512, 0) in `config\models.json` und `config\benchmark.json`.
   Nach der Messung wieder entfernen.

### Gemessen

- `Test-Model.ps1` `local-coder` auf b12433: 58,7 Tok./s (MTP 60 % angenommen), Werkzeug
  und Bild in Ordnung, 15596 und 10417 MiB. Gleich wie auf b12359 (59,3).
- Die fünf Aufgaben je dreimal, Lauf `b12433`: **13 / 15 in 4463 s**, Regeln 60 / 66
  (91 %). Vergleich `stufe4` auf b12359: 14 / 15 in 4903 s, 89 %. Die Fehlschläge nur
  bei `longcontext` (1 / 3 statt 2 / 3); bei drei Läufen ist das kein belastbarer
  Unterschied. Der neue Build bleibt.
- Nur Tempo, noch keine Qualität: `local-coder-rb2048` 57,5 Tok./s, `local-coder-rb0`
  72,8 Tok./s (82 % der MTP-Entwürfe angenommen statt 60 %).

### Offen

- Q4 an den Aufgaben messen (`planner` und die fünf neueren), danach die Profile
  `-rb*` entfernen.

## 2026-11-16: Feinschliff, erster Teil (Stufe 4 des Zukunftsplans)

### Anlass

Der Nutzer gab Stufe 4 frei und bat danach, zügig abzuschließen, um mit dem Coder zu
arbeiten. Erledigt sind E1, E2, G1, G2 und Q9; Q5 ist begonnen.

### Durchgeführt

1. **`config\models.json`:** `mmproj-device: CUDA1` und `ctx-size: 131072` für
   `local-coder`, `local-fast` und `local-qwen38`; neues Vergleichsprofil
   `local-coder-q5` (Q5_K_M, 64k, Aufteilung 66/34).
2. **Abschlussprüfung:** `Check-Stop.ps1` liest die in der Antwort geänderten Dateien aus
   dem Verlauf und lässt Punkte der Erinnerung weg, die damit erledigt sind
   (`reminderPoints` in `config\agent.json`, Punkte `- [name]` in `config\abschluss.md`).
   Ist kein Punkt offen, kommt keine Erinnerung. Zwei neue Fälle in `Test-Setup.ps1`.
3. **Q5_K_M geladen** von der Quelle des bisherigen Modells (18,4 GiB), SHA-256
   `9d309b8f...5a4285` gleich der Angabe der Quelle, mit `Add-Model.ps1` eingehängt.

### Gemessen

Tabellen und Bewertung: [modellwahl.md](modellwahl.md), erster Abschnitt. In Kürze:

- Bild-Encoder auf der 3060: 1,2 GB auf der 5070 Ti frei, Bilder gleich schnell.
- 128k Kontext: 15,6 und 10,4 GB, Tempo gleich; alle drei Profile laden.
- GPU-Aufteilung bei 64k: 79/21 bringt 65,5 statt 61 Tok./s; verworfen zugunsten des
  Kontexts. MTP-Länge: 4 bleibt der beste Wert.
- Lauf `stufe4` (128k, sparsamere Erinnerung): 14 / 15 in 4903 s, Regeln 59 / 66 (89 %),
  README und Test 15 / 15; `longcontext` 2 / 3. Vorher (`stufe3b`): 12 / 15 in 5951 s, 85 %.
- Abschluss: `Test-Model.ps1` 59,3 Tok./s, Tool-Aufruf und Bild in Ordnung, 15596 und
  10417 MiB; `Test-Setup.ps1` bestanden; `Test-Guard.ps1` 89 von 89.

### Fehler und Erkenntnisse

- **Ruhezustand während einer Messung.** Der zweite Lauf von `stufe4-128k` steht mit
  41474 s im Bericht; der Wert ist unbrauchbar.
- **Kleinstes Fenster zählt.** `claude-local` meldet Claude Code das kleinste `ctx-size`
  der Profile aus der Modellauswahl. Für die Messung mit 128k mussten deshalb alle drei
  Profile umgestellt werden.
- **Q5_K_M mit 96k lädt nicht** (`failed to create context`); `82,18` als Aufteilung
  ebenfalls nicht.

### Offen

- Stufe 4, Rest: E3 bis E5, G3 bis G5, Q4, Q6; Qualität von Q5 gegen Q4.
- `local-fast` und `local-qwen38` mit 128k an den Aufgaben; Tab-Vervollständigung von
  Continue neben `local-coder` mit 128k.

## 2026-11-15 abends: Arbeitsweise (Stufe 3 des Zukunftsplans)

### Anlass

Der Nutzer gab Stufe 3 frei: Projektvorlage (N1), kurze `CLAUDE.md` (N2),
Entscheidungsdateien (N3), ein Prüfbefehl je Projekt (N4), feste Abläufe als Befehle (N5),
Prüfung nach jeder Antwort (Q3), Hinweise zu PowerShell 5.1 (Q8).

### Durchgeführt

1. **Hinweise zu PowerShell 5.1** als Abschnitt in `config\entwicklungsregeln.md`.
2. **Abschlussprüfung:** `scripts\hooks\Check-Stop.ps1` als `Stop`-Hook. Nach einer
   Antwort mit Dateiänderungen führt er den Prüfbefehl des Projekts aus (falls vorhanden)
   und gibt Fehler an das Modell zurück, höchstens dreimal; einmal je Antwort erinnert er
   mit `config\abschluss.md` an Test, README, Einstellungen und Aufräumen. Einstellungen
   unter `stopCheck` in `config\agent.json`, Bausteine in `scripts\lib\Quality.ps1`.
3. **Befehle** `/lokal:feature`, `/lokal:bugfix`, `/lokal:pruefen` als Plugin in
   `config\befehle\`, geladen mit `--plugin-dir` nur für `claude-local`.
4. **Projektvorlage** in `templates\projekt\` (`gemeinsam`, `python`, `powershell`) mit
   README, `CLAUDE.md`, `docs\architektur.md`, `docs\entscheidungen\`, `CHANGELOG.md`,
   `config\settings.json`, erstem Test, Prüfbefehl `scripts\Check.ps1` (Schritte in
   `config\check.json`) und Git-Hook. `scripts\New-Project.ps1` legt daraus ein Projekt an,
   Einstellungen in `config\projects.json`, Bausteine in `scripts\lib\Projects.ps1`.
5. **`scripts\Test-Templates.ps1`:** legt je Sprache ein Projekt an und prüft Platzhalter,
   Prüfbefehl, ersten Commit und dass ein eingebauter Fehler Prüfbefehl und Commit
   scheitern lässt.
6. **Benchmark:** `-Overlay <Name>` legt Dateien aus `benchmark\overlays\<Name>\` in den
   Arbeitsordner (hier `projekt`: `CLAUDE.md`, Prüfbefehl), `-Prefix <Text>` stellt dem
   Auftrag einen Befehl voran. `Test-Tasks.ps1 -Overlay projekt` prüft die Aufgaben damit.
7. **`Test-Setup.ps1`:** neuer Abschnitt für Abschlussprüfung und Befehle.
8. **Dokumentation:** neu [projekte.md](projekte.md); [agent.md](agent.md),
   [modellwahl.md](modellwahl.md), [roadmap.md](roadmap.md), [erweitern.md](erweitern.md),
   `architektur.md`, `README.md`, `CLAUDE.md`.

### Gemessen

`local-coder`, die fünf neueren Aufgaben je dreimal, llama.cpp b12359, Claude Code 2.1.325.

| | `stufe2` (vorher) | `stufe3` | `stufe3b` | `stufe3-projekt` |
|---|---|---|---|---|
| Bestanden | 9 / 15 | 11 / 15 | 12 / 15 | 11 / 15 |
| `psscript` | 0 / 3 | 3 / 3 | 3 / 3 | 3 / 3 |
| `longcontext` | 0 / 3 | 0 / 3 | 0 / 3 | 0 / 3 |
| `readme` | 7 / 15 | 14 / 15 | 13 / 15 | 12 / 15 |
| `tests` | 6 / 15 | 7 / 15 | 13 / 15 | 13 / 15 |
| `config` | 0 / 6 | 0 / 6 | 0 / 6 | 5 / 6 |
| Regeln eingehalten | 65 % | 77 % | 85 % | 91 % |
| Zeit | 3970 s | 5494 s | 5951 s | 6555 s |

`stufe3`: Hinweise, Abschlussprüfung mit erster Erinnerung, Befehle geladen. `stufe3b`:
Erinnerung geschärft. `stufe3-projekt`: dazu `CLAUDE.md` und Prüfbefehl im Arbeitsordner.
Lauf `stufe3-befehl` (`extend` dreimal mit `/lokal:feature`): 2 / 3 in 914 s, Regeln
15 / 15. Bewertung: [modellwahl.md](modellwahl.md).

`Test-Setup.ps1`, `Test-Tasks.ps1`, `Test-Templates.ps1` bestanden, `Test-Guard.ps1` 89 von
89 Fällen.

### Fehler und Erkenntnisse

- **Erste Erinnerung zu weich.** Auf „Test geschrieben und ausgeführt?“ hin schrieb das
  Modell ein Prüfskript, führte es aus und löschte es wieder. Die Regel `tests` stieg erst,
  als die Erinnerung das ausdrücklich ausschloss (7 auf 13 von 15).
- **`config` braucht einen Ort, keine Regel.** `DEFAULT_WAREHOUSE = "main"` blieb trotz
  Regel und Erinnerung im Code, bis eine `CLAUDE.md` sagte, wo Einstellungen liegen.
- **`ExitCode` leer unter PowerShell 5.1.** Nach `Start-Process -PassThru` und
  `WaitForExit` war `ExitCode` leer, der Hook hielt einen bestandenen Prüfbefehl für
  gescheitert. Abhilfe: vor dem Warten `$null = $process.Handle` lesen.
- **Befehle tragen den Namen des Plugins.** `/bugfix` wird in `claude-local -p` nicht
  erkannt, `/lokal:bugfix` schon.
- **Keine globale Git-Identität auf diesem Rechner.** Der erste Commit eines neuen
  Projekts scheiterte; `New-Project.ps1` übernimmt Name und Adresse jetzt aus diesem
  Repository, wenn das neue keine hat.
- **Mehr Runden füllen den Kontext.** Mit Projektvorlage dauerte `psscript` 842 bis 900 s
  statt 507 bis 572 s; ein Lauf erreichte das Zeitlimit, einer endete mit `blocking_limit`.

### Offen

- Befehle und Abschlussprüfung in einer echten Sitzung am Terminal (bisher nur `-p`).
- `/lokal:bugfix`, `/lokal:pruefen` und Entscheidungsdateien sind nicht gemessen (N8).
- Linter, Suche nach Geheimnissen und Prüfung der Abhängigkeiten im Prüfbefehl (N9, S7).
- Abschlussprüfung billiger machen (Q9); `longcontext` braucht mehr Kontext (E2).
- `local-fast` und `local-qwen38` sind mit der neuen Arbeitsweise nicht gemessen.

## 2026-11-15 nachmittags: Messbarkeit (Stufe 2 des Zukunftsplans)

### Anlass

Der Nutzer gab Stufe 2 frei: Aufgaben, die dem echten Einsatz gleichen (Q1), und eine
Zahl dafür, ob das Modell die Arbeitsregeln einhält (Q2).

### Durchgeführt

1. **Fünf neue Aufgaben** in `benchmark\tasks\`: `extend`, `refactor`, `psscript`,
   `screenshot`, `longcontext` (Beschreibung: [erweitern.md](erweitern.md)). Jede hat eine
   Musterlösung in `solution\`.
2. **Regeltreue:** `benchmark\lib\rulecheck.py` mit Bausteinen für sechs Regeln (`readme`,
   `tests`, `config`, `docstrings`, `headers`, `nodeadcode`). Die Prüfung einer Aufgabe
   gibt sie als Zeile `RULES {...}` aus; bestanden oder nicht hängt davon nicht ab.
3. **`scripts\Test-Tasks.ps1`:** prüft ohne Modell, dass jede Vorlage durchfällt und jede
   Musterlösung besteht, mit allen Regeln eingehalten. Gemeinsame Bausteine in
   `scripts\lib\Tasks.ps1` (`New-TaskWorkCopy`, `Invoke-TaskCheck`), die auch der Benchmark
   benutzt.
4. **`scripts\Benchmark-Models.ps1`:** erlaubte Befehle und Zeitlimit je Aufgabe aus
   `config\benchmark.json` (`allowedTools`, `taskTimeoutSeconds`), Ausgabe-Tokens und
   Regeln je Lauf in `results.jsonl`, im Bericht die Spalte „Regeln eingehalten“ und der
   Abschnitt „Arbeitsregeln“.
5. **Dokumentation:** [erweitern.md](erweitern.md) (Aufgaben, Regeln, neue Aufgabe
   anlegen), [modellwahl.md](modellwahl.md) (Bewertung), [roadmap.md](roadmap.md) (Q1 und
   Q2 gestrichen, Ausgangslage, neu Q8), `architektur.md`, `README.md`, `CLAUDE.md`.

### Gemessen

Lauf `stufe2`, jede Aufgabe dreimal, llama.cpp b12359, Claude Code 2.1.325.

| Aufgabe | `local-coder` | `local-fast` |
|---|---|---|
| `extend` | 3 / 3 | 1 / 3 |
| `refactor` | 3 / 3 | 2 / 3 |
| `screenshot` | 3 / 3 | 0 / 3 |
| `psscript` | 0 / 3 | 0 / 3 |
| `longcontext` | 0 / 3 | 0 / 3 |
| Summe | 9 / 15 in 3970 s | 3 / 15 in 3679 s |
| Regeln eingehalten | 43 / 66 (65 %) | 34 / 66 (52 %) |

Rohwerte: `local-coder` Laden 9,3 s, 63,3 Tok./s, Einlesen 1321 Tok./s, 14718 und 7529 MiB;
`local-fast` Laden 17,1 s, 129,1 Tok./s, Einlesen 3497 Tok./s, 15108 und 9311 MiB.
Zeiten je Lauf und Quote je Regel: [modellwahl.md](modellwahl.md), [benchmark.md](benchmark.md).

Das Ziel von Q1 (mindestens zwei neue Aufgaben, die `local-coder` nicht jedes Mal besteht)
ist erreicht, das von Q2 (Quote je Modell im Bericht) ebenfalls. `Test-Tasks.ps1`: alle
neun Aufgaben in Ordnung. `Test-Setup.ps1`: alle Prüfungen bestanden. Nach den Läufen war
der GPU-Speicher frei (7 und 0 MiB).

### Fehler und Erkenntnisse

- **Drei Fehler in den eigenen Prüfungen.** Zwei fand der Selbsttest vor dem ersten
  Modell-Lauf: Die Prüfung von `refactor` verlangte eine bestimmte Reihenfolge der
  Schlüssel und scheiterte danach an Zeilenenden von Windows; und Python benutzte in einer
  frischen Arbeitskopie veraltete `__pycache__`-Dateien der Vorlage (gleiche Größe, gleiche
  Sekunde), sodass die Musterlösung von `longcontext` falsch erschien. `New-TaskWorkCopy`
  entfernt diese Ordner jetzt. Den dritten fand erst die Messung: Die Musterlösung für
  Irland widersprach der Änderungsliste (zu schweres Paket bei kostenlosem Versand). Der
  betroffene Lauf (`local-coder`, `longcontext` Nr. 2) scheiterte auch an Italien; sein
  Urteil ändert sich nicht, der gespeicherte Prüftext nennt Irland aber zu Unrecht.
- **„Autocompact is thrashing“.** Bei `longcontext` beendete Claude Code vier von sechs
  Läufen selbst (`terminal_reason: rapid_refill_breaker`): Der Kontext war dreimal
  hintereinander binnen drei Runden nach dem Komprimieren wieder voll. Geändert wurde in
  diesen Läufen fast nichts.
- **PowerShell 5.1:** sechs Läufe, sechs verschiedene Fehler, alle an Eigenheiten der
  Shell (stderr, Exit-Code, Liste mit einem Eintrag, ungewollte Ausgabe).
- **`local-fast` meldet Erfolg, wo keiner ist.** Bei `screenshot` berichtete es in jedem
  Lauf, beide Aufrufe aus dem Bild gingen jetzt. Zweimal hatte es den ersten ohne `0.5h`
  nachgestellt, einmal `0.5h` als nicht dokumentiert beiseitegelassen.
- **Abgelehnte Aufrufe im Benchmark.** Ohne Nutzer am Terminal gilt alles Unerlaubte als
  abgelehnt. Betroffen waren Aufrufe mit `cd ... &&` vor dem Befehl, Schreibversuche nach
  `/tmp` und ein Pfad mit falscher Groß- und Kleinschreibung (`E:\LlamaCPP`). Kein Lauf
  scheiterte nachweislich allein daran.
- **Die Regeln wirken ungleich:** Beschreibungen und „kein toter Code“ fast immer, README
  und Tests in weniger als der Hälfte der Läufe, der Wert in der Konfigurationsdatei nie.

### Offen

- `local-qwen38` ist auf den neuen Aufgaben nicht gemessen.
- Die Regelprüfung ist mechanisch: Sie sieht, ob etwas geschehen ist, nicht wie gut.
- Drei Läufe je Aufgabe sind wenig; für Vergleiche in Stufe 3 und 4 dieselben Aufgaben
  mit demselben Verfahren wiederholen.
- Ob die Arbeitsregeln überhaupt etwas bewirken, zeigt erst ein Lauf ohne
  `entwicklungsregeln.md` (P5).
- Stufe 3 (Arbeitsweise) wartet auf die Freigabe des Nutzers.

## 2026-11-15 vormittags: Schutznetz (Stufe 1 des Zukunftsplans)

### Anlass

Der Nutzer gab Stufe 1 des Zukunftsplans frei, mit der Vorgabe: Der Schutz soll ihn
schützen, nicht andere, und das Modell nicht in seiner Arbeit beschränken. Daraus der
Grundsatz in [sicherheit.md](sicherheit.md) und in `CLAUDE.md`: geschützt werden der eigene
Rechner und die eigenen Daten; keine Regeln zu Inhalten; normale Arbeit im Projektordner
bleibt frei; im Zweifel Rückfrage statt Sperre.

### Durchgeführt

1. **Schlüssel für den Server (S1):** `requireApiKey` und `corsOrigins` in
   `config\server.json`. Der Schlüssel entsteht beim ersten Start in
   `E:\LlamaCpp\run\api-key.txt` und geht über die Variable `LLAMA_API_KEY` an den Server.
   `Invoke-ServerApi`, `claude-local` und `Install-Continue.ps1` schicken ihn mit;
   `config\continue.config.yaml` enthält nur einen Platzhalter.
2. **Wächter vor jedem Werkzeug-Aufruf (S2, S3):** `scripts\hooks\Guard-Tool.ps1` als
   `PreToolUse`-Hook, Regeln in `config\guard.json`, eingehängt über die Einstellungsdatei,
   die `claude-local` für jeden Start erzeugt (`lib\Safety.ps1`). Drei Sperren
   (Laufwerke und Systemordner löschen, formatieren, Startkonfiguration und Sicherungen),
   sonst Rückfragen (Löschen außerhalb des Projekts, Git-Befehle, die Arbeit verwerfen,
   Laden und Ausführen aus dem Netz, Registrierung, Virenschutz, Autostart, Zugangsdaten).
3. **Git-Hinweis beim Start (S4):** `gitCheck` in `config\agent.json`.
4. **`scripts\Test-Setup.ps1` (P1)** und **`scripts\Test-Guard.ps1`** mit 89 Fällen in
   `tests\guard-cases.json`.
5. **Versionen mitschreiben (P2):** `Test-Model.ps1` und der Benchmark nennen die Version
   von Claude Code (derzeit 2.1.325).
6. **Continue:** Konfiguration mit Schlüssel neu installiert (alte Datei gesichert als
   `config.yaml.bak-20261115-083931`).
7. **Zukunftsplan angepasst:** erledigte Punkte gestrichen, S7 an den Grundsatz angepasst
   (keine Rückfrage bei jeder Paketinstallation), neu S8 und S9.

### Gemessen

- **Schlüssel:** Ohne Schlüssel antworten Server und Modell-Prozess mit 401, mit Schlüssel
  normal; `/health` bleibt offen. Die Warnung `no API key is set and CORS allows all
  origins` steht nicht mehr im Server-Protokoll. `Test-Model.ps1` mit Schlüssel:
  `local-coder` 59,4 Tok./s, Tool-Aufruf und Bild in Ordnung.
- **Modell-Prozesse:** Mit `--api-key-file` am Router allein nehmen die Modell-Prozesse auf
  ihren eigenen Ports weiter Anfragen ohne Schlüssel an; ein Eintrag in der Modellliste
  wird nicht weitergereicht. Erst die Variable `LLAMA_API_KEY` wirkt auf beide.
- **Wächter:** 89 von 89 Fällen wie erwartet, darunter 32 normale Arbeitsschritte, die frei
  bleiben. Ein Aufruf kostet 266 ms (Mittel aus fünf).
- **In echten Sitzungen (`claude-local -p`):** Datei anlegen, mit Python starten und
  `rm -rf __pycache__` laufen ungestört (13 s). `format Q: /?` wurde dreimal gesperrt.
  `git reset --hard` und das Lesen einer Datei `tresor.kdbx` wurden nicht ausgeführt; das
  Modell bekam die Begründung des Wächters. Alle vier Entscheidungen stehen in
  `E:\LlamaCpp\logs\guard.log`.
- **Kaputte `guard.json`:** Der Wächter antwortet mit Rückfrage (`guard-error`), nicht mit
  Durchlassen.
- **`Test-Setup.ps1`** meldet eine ungültige JSON-Datei, ein Skript mit Umlaut und ein
  Skript mit verlorenem Kommentarzeichen, jeweils mit Exit-Code 1.

### Fehler und Erkenntnisse

- **Das Modell umgeht eine Sperre von sich aus.** Nach der dritten Ablehnung von
  `format Q: /?` rief es die Hilfe auf anderem Weg ab. Hier harmlos, aber es zeigt die
  Grenze eines Wächters, der Befehle an der Schreibweise erkennt (Zukunftsplan S9, S6).
- **Ein Testfall war falsch gewählt:** `rm -rf ../guard-test-dummy` lief durch, weil der
  Testordner im Temp-Ordner lag und dort Löschen frei ist. Das Verhalten ist gewollt.
- **Zweimal ging beim Einfügen eines Kommentars das `#` verloren** (`Config.ps1`,
  `Server.ps1`), PowerShell meldete erst beim Aufruf der Funktion einen Fehler.
  `Test-Setup.ps1` prüft jetzt darauf.

### Offen

- **Rückfrage in einer Sitzung am Terminal** nicht selbst gesehen: Geprüft sind nur Läufe
  ohne Nutzer, in denen eine Rückfrage als Nein zählt (Zukunftsplan S8).
- **Continue mit Schlüssel** nicht in VS Code ausprobiert. Der Autocomplete-Eintrag schickt
  den Schlüssel doppelt (als `apiKey` und als Kopfzeile), weil nicht geprüft ist, welchen
  Weg der Anbieter `llama.cpp` von Continue nimmt.
- **Regel für das Modell „vor größeren Umbauten committen“** aus dem Plan ist nicht in
  `entwicklungsregeln.md` aufgenommen: Ihre Wirkung auf die Benchmark-Aufgaben ist nicht
  gemessen (mit Q2 nachholen).
- Die Schutzregeln sind an 89 gedachten Fällen geprüft, nicht an Wochen echter Arbeit.

## 2026-11-15: Bilder, GPU-Speicher nach der Sitzung, Zukunftsplan

### Anlass

Der Nutzer meldete: Das lokale Modell erkennt weiterhin keine Bilder, und nach `exit` bleibt
der GPU-Speicher belegt. Dazu der Wunsch nach einem Zukunftsplan.

### Durchgeführt

1. **Bild-Encoder eingetragen** (vom Vorabend, bisher nicht committet): `mmproj` in den drei
   Agenten-Profilen, `Get-ModelProfile` löst den Dateinamen auf, `Start-Server` lädt ein
   Modell ohne Bild-Eingabe, wenn die Datei fehlt. `Test-Model.ps1` hat die neue Zeile
   `image input`.
2. **Eigentliche Ursache des Bildfehlers behoben:** Kommt ein Tool-Ergebnis zusammen mit
   Text in einer Nachricht, stellt `llama-server` den Text vor das Ergebnis. Die eingebaute
   Vorlage von Qwen 3.6 bricht dann mit Fehler 500 ab. Neu:
   `config\templates\qwen3.6-agent.jinja` für `local-coder` und `local-fast`; derselbe Block
   in `qwen3.8-agent.jinja`. Beschreibung in [modelle.md](modelle.md), Abschnitt „Chat-Vorlage“.
3. **Kleine Bilder werden hochgerechnet:** `image-min-tokens = 256` in den drei Profilen.
4. **GPU-Speicher wird frei, wenn die letzte Sitzung endet:** `onExit` in
   `config\agent.json` (`unload`, `stop`, `keep`), Schalter `-OnExit` für einen Aufruf, neuer
   Baustein `scripts\lib\Session.ps1`, `Stop-Models` in `lib\Server.ps1`. Der Benchmark ruft
   `claude-local` mit `-OnExit keep` auf. Beschreibung in [agent.md](agent.md).
5. **Leerlauf-Grenze:** `sleep-idle-seconds = 1800` für alle Profile, als Netz für
   geschlossene Fenster und Abstürze ([backend.md](backend.md)).
6. **Zukunftsplan:** [roadmap.md](roadmap.md).

### Gemessen

- **Fehlerbild:** Das Server-Protokoll der Sitzung vom Vorabend zeigt fünfmal
  `A tool message must follow an assistant or tool message` (Claude Code wiederholt die
  Anfrage). Nachgestellt mit direkten Anfragen an `/v1/messages`: Tool-Ergebnis plus Text
  schlägt immer fehl, mit und ohne Bild; ein Tool-Ergebnis allein geht. Der Test vom
  Vorabend schickte nur die zweite Form und meldete deshalb `OK`. Er schickt jetzt die
  erste.
- **Nach der Korrektur:** 17 Formen von Nachrichten (Bild allein, mit Text, zwei Werkzeuge,
  zwei Bilder, eingefügtes Bild, Systemnachricht dazwischen) werden alle angenommen.
- **Lesegenauigkeit** mit `local-coder`: 12 kleine Bilder mit einer Zahl, ohne
  `image-min-tokens` 5 richtig, mit 256 und mit 1024 je 12. 8 Screenshots eines Terminals
  in jeder Einstellung 8 richtig.
- **`Test-Model.ps1`** mit der endgültigen Konfiguration: `local-coder` 65,1 Tok./s,
  `local-fast` 136,7, `local-qwen38` 54,3; Tool-Aufruf und Bild bei allen in Ordnung.
- **Ganzer Weg:** `claude-local -p` mit dem Auftrag, eine Zahl aus einer Bilddatei zu
  lesen, antwortet richtig. Danach meldet `claude-local`
  `models unloaded, GPU memory used now (MiB): RTX 5070 Ti 7, RTX 3060 0`
  (vorher 14268 und 7633).
- **Zwei Sitzungen:** Läuft eine zweite, bleibt das Modell geladen; nach deren Ende räumt
  die letzte auf. Die Markierung eines beendeten Prozesses wird gelöscht.
- **Leerlauf-Grenze** (Probe mit 15 s): 14718 und 7529 MiB fallen auf 226 und 105 MiB,
  die nächste Anfrage antwortet nach 7,2 s.
- Der Server ohne geladenes Modell belegt keinen GPU-Speicher.

### Fehler und Erkenntnisse

- **Ein Test, der nur die einfache Form prüft, beweist wenig.** Der Bild-Test bestand am
  Vorabend, die echte Sitzung scheiterte. Maßgeblich ist, was Claude Code wirklich schickt;
  mitgeschnitten mit einem Zwischenserver.
- **Der Fehler betraf nicht nur Bilder,** sondern jedes Tool-Ergebnis mit angehängtem Text,
  also vor allem interaktive Sitzungen. Die Läufe des Benchmarks (`-p`) trafen ihn nicht.
- **Die Umwandlung in llama.cpp ist auch im aktuellen Stand so** (`server-chat.cpp`,
  verglichen mit `master`). Ein Update behebt es nicht.
- **`models.json` war kurz ungültig** (ein Rückstrich zu wenig), der Server startete
  nicht. Daraus Punkt P1 im Zukunftsplan.
- Während der Arbeit lief eine zweite Sitzung am Erscheinungsbild im selben Repository;
  die Änderungen an `claude-local.ps1` und `_common.ps1` wurden abgestimmt.

### Offen

- **Quelle der drei `mmproj`-Dateien** ist nicht festgehalten, Prüfsummen nicht geprüft
  (Zukunftsplan S5).
- **Einfügen eines Bildes mit Alt+V** in einer interaktiven Sitzung nicht selbst
  ausprobiert; geprüft sind dieselbe Nachrichtenform über die Schnittstelle und der Weg
  über `Read`.
- **Beenden mit geschlossenem Fenster** räumt nicht auf, dann greift die Leerlauf-Grenze.
- Die Wirkung von `sleep-idle-seconds` auf lange Denkpausen in einer Sitzung (Neueinlesen
  des Kontexts) ist nicht gemessen.
- Alle Punkte des Zukunftsplans.

## 2026-11-14 nachts: Erscheinungsbild „Nachtschicht“

### Durchgeführt

1. **Ein Aussehen für Shell, `claude` und `claude-local`:** drei Lichtstimmungen, deren
   Farbtemperatur zeigt, wo gerechnet wird (Werkbank = Shell, Glut = lokales Modell,
   Fernlicht = Cloud). Alle Farben, Zeichen und Texte in `config\style.json`,
   Beschreibung in [stil.md](stil.md).
2. **Neue Skripte:** `Install-Style.ps1` (wendet an, `-Remove` nimmt zurück,
   `-PreviewDir` zeigt nur), `Install-Font.ps1` (IBM Plex Mono für den Benutzer),
   `style\Shell.ps1` (Eingabezeile, Begrüßung mit beiden Grafikkarten),
   `style\Statusline.ps1` (Statuszeile von Claude Code), Bausteine in `lib\Style.ps1`.
3. **`claude-local`** tönt das Fenster für die Dauer der Sitzung warm, übergibt Thema und
   Statuszeile für diesen Start und meldet sich in Glutfarben. Bei umgeleiteter Ausgabe
   bleiben die bisherigen Textzeilen, der Benchmark sieht also dasselbe wie zuvor.
4. **Außerhalb des Repositorys geändert** (jeweils mit einmaliger Sicherung
   `<Name>.vor-nachtschicht`): `settings.json` von Windows Terminal (Schema, Thema,
   Profil „Nachtschicht“ als Standard) und `%USERPROFILE%\.claude\settings.json` (`theme`,
   `statusLine`, `spinnerVerbs`). Neu: zwei Dateien in `%USERPROFILE%\.claude\themes\`,
   16 Schriftdateien in `%LOCALAPPDATA%\Microsoft\Windows\Fonts`,
   `%LOCALAPPDATA%\Nachtschicht\glut.png`. Die Ausführungsrichtlinie des Systems und das
   PowerShell-Profil sind unverändert.

### Gemessen

Start der Shell mit Begrüßung etwa 440 ms (PowerShell allein 134 ms), eine Eingabezeile
etwa 30 ms, ein Lauf der Statuszeile etwa 380 ms. Ein zweiter Lauf von `Install-Style.ps1`
ändert die Dateien nicht mehr.

### Offen

- **Am Bildschirm nicht geprüft.** Eingerichtet wurde ohne Blick auf das Fenster. Zu
  bestätigen: Farbwirkung, Schriftbild, ob das Fenster beim Start von `claude` und
  `claude-local` die Stimmung wechselt und danach zurückkehrt, ob Claude Code die Themen
  ohne Meldung annimmt.
- `claude-local` mit dem neuen Aussehen ist nur in Teilen geprüft (Startmeldung,
  Einstellungsdatei, Steuerfolgen), nicht als ganze Sitzung: Der Server war durch eine
  parallele Arbeit belegt.

## 2026-11-14 abends: Ollama entfernt, Schleife geklärt, neue Modelle

### Durchgeführt

1. **Ollama deinstalliert:** Programm, `E:\Ollama` (64 GB), `%USERPROFILE%\.ollama`, der
   Autostart-Eintrag und die Benutzer-Variablen `OLLAMA_*` und `LLAMA_ARG_TENSOR_SPLIT`
   sind entfernt. Die Modelle in `E:\LlamaCpp\models` blieben erhalten (Hardlinks).
2. **Autostart geprüft:** Für `llama-server` gibt es keinen Eintrag unter `Run`, im
   Autostart-Ordner, als Dienst oder als geplante Aufgabe. Nichts zu ändern.
3. **Schleife von qwen3-coder 30B geklärt:** angefangenes `<tool_call>` am Ende der Antwort,
   llama.cpp erzwingt daraus einen Aufruf. Erklärung in [modellwahl.md](modellwahl.md).
4. **Schlanker Werkzeugsatz:** `claude-local` gibt nur `Bash, Read, Edit, Write, Glob, Grep`
   frei und schaltet Auto-Memory und mitgelieferte Skills ab (`tools` und `env` in
   `config\agent.json`, [agent.md](agent.md)).
5. **Neue Benchmark-Aufgabe `planner`**, schwerer als die bisherigen. Zeitlimit je Lauf
   600 statt 420 s. `Benchmark-Models.ps1` hat den neuen Schalter `-Tasks`.
6. **Drei Kandidaten gemessen:** Qwen 3.6 27B Heretic v2 und Qwen 3.6 35B-A3B Heretic (von
   Hugging Face geladen, Prüfsummen geprüft) und gpt-oss 20B (lag schon beim Projekt Jarvis,
   als Hardlink eingebunden).
7. **Profile umgestellt:** `local-coder` = Qwen 3.6 27B, `local-fast` = Qwen 3.6 35B-A3B,
   neu `local-qwen38` = das bisherige Standardmodell. Profile für qwen3-coder 30B und
   gpt-oss 20B entfernt, die Dateien nicht. `/model` zeigt drei Einträge. Continue neu
   installiert (alte Datei gesichert als `config.yaml.bak-20261114-205326`).
8. **Messdaten umbenannt:** In `logs\benchmark\results.jsonl` tragen die llama.cpp-Einträge
   die neuen Profilnamen, damit der Bericht zur Konfiguration passt
   (Zuordnung in [modellwahl.md](modellwahl.md)).

### Gemessen

Tabelle und Bewertung in [modellwahl.md](modellwahl.md). Kurz: Qwen 3.6 27B bestand alle
6 Läufe von `planner` in 135 bis 189 s, Qwen 3.8 27B 5 von 6 in 216 bis 600 s, Qwen 3.6
35B-A3B und gpt-oss 20B je 1 von 3. Die leichten Aufgaben bestehen alle vier.

`Test-Model.ps1` nach der Umstellung: `local-coder` 60,5 Tok./s, `local-fast` 140,8 Tok./s,
`local-qwen38` 51,8 Tok./s, Tool-Aufruf bei allen in Ordnung.

### Offen

- **Datei ohne Profil** in `E:\LlamaCpp\models`: `gpt-oss-20b-MXFP4.gguf` (Hardlink, kein
  eigener Platz). `qwen3-coder-30b-Q4_K_M.gguf` (18,6 GB) wurde auf Wunsch des Nutzers
  am selben Abend gelöscht.
- **Ablehnungsrate** der neuen Modelle nicht selbst geprüft.
- **Ein Durchgang mit 37 statt 60 Tok./s** bei Qwen 3.6 27B direkt nach einem Neustart des
  Servers, Ursache nicht geprüft.
- Weiter ungeprüft: `/model` in einer interaktiven Sitzung, Continue in VS Code.

## 2026-11-14 nachmittags: Umbau von Ollama auf llama.cpp, Arbeitsregeln

### Durchgeführt

1. **llama.cpp installiert:** Build b12359 (CUDA 13.5) nach `E:\LlamaCpp\b12359`, Prüfsummen
   gegen GitHub geprüft. Skript: `scripts\Install-LlamaCpp.ps1`.
2. **Modelle übernommen:** Die drei GGUF-Dateien aus dem Ollama-Bestand als Hardlinks nach
   `E:\LlamaCpp\models` gelegt (`scripts\Add-Model.ps1`). Nichts neu geladen, nichts gelöscht.
3. **Server im Router-Modus:** Ein `llama-server` auf `127.0.0.1:8080`, der Modelle bei Bedarf
   lädt und entlädt. Einstellungen in `config\server.json`, Profile in `config\models.json`.
4. **GPU-Aufteilung je Modell:** `local-coder` 70:30, `local-fast` 65:35, Autocomplete allein
   auf der 3060.
5. **Chat-Vorlage angepasst:** `config\templates\qwen3.8-agent.jinja`, siehe unten.
6. **`claude-local` umgestellt:** Verbindung zum neuen Server, Kontextgröße aus `models.json`,
   Modellauswahl für `/model` übernommen.
7. **Arbeitsregeln für das lokale Modell:** `config\entwicklungsregeln.md` (544 Tokens) wird
   jeder Sitzung angehängt. Beide Modelle geben die Regeln auf Nachfrage richtig wieder.
8. **Skripte neu gegliedert:** gemeinsame Bausteine in `scripts\lib\` (`Config.ps1`,
   `Server.ps1`, `Measure.ps1`). Neu: `Start-`, `Stop-`, `Restart-Server.ps1`. `Test-Model.ps1`
   und `Benchmark-Models.ps1` auf llama.cpp portiert. Die Ollama-Skripte, `modelfiles\` und
   `config\ollama.env.json` entfernt (Git-Historie bis `fbb8c80`).
9. **Continue umgestellt:** `config\continue.config.yaml` zeigt auf den neuen Server.
10. **Dokumentation neu:** README, `architektur.md`, `einrichtung.md`, `erweitern.md`; neu
    `backend.md`, `modelle.md`, `agent.md` und `CLAUDE.md` mit den Regeln für dieses Projekt.

### Gemessen

Lauf `llamacpp`, jede Aufgabe dreimal ([modellwahl.md](modellwahl.md)):

| Profil | Bestanden | Zeit | Vorher über Ollama |
|---|---|---|---|
| `local-coder` | 9 / 9 | 431 s | 9 / 9 in 993 s |
| `local-fast` | 7 / 9 | 1709 s | 3 / 3 in 172 s (ein Lauf je Aufgabe) |

Der Vergleich bei `local-coder` ist nicht sauber: Backend, GPU-Aufteilung, Chat-Vorlage und
Arbeitsregeln haben sich zugleich geändert.

Schnittstellen für Continue mit direkten Anfragen geprüft: Chat über
`/v1/chat/completions` (Streaming) und Vervollständigung über `/completion` (183 Tok./s).
`local-coder` und das Autocomplete-Modell sind gleichzeitig geladen (13,5 und 8,9 GB belegt).

### Fehler und Erkenntnisse

- **Die Chat-Vorlage von Qwen 3.8 lehnt spätere Systemnachrichten ab**
  (`System message must be at the beginning.`). Claude Code schickt solche Nachrichten mitten
  im Gespräch, jede Anfrage endete mit Fehler 500. Ollama umgeht das mit einem eigenen
  Renderer. Lösung: eigene Vorlage mit einer geänderten Stelle.
- **`LLAMA_ARG_TENSOR_SPLIT` aus der Ollama-Zeit** steht in der Benutzer-Umgebung und wird von
  jedem `llama-server` gelesen. `Start-Server` entfernt `LLAMA_ARG_*` vor dem Start.
- **Benchmark-Arbeitsordner im Repository verfälscht die Aufgaben:** Claude Code lädt die
  `CLAUDE.md` aller übergeordneten Ordner. Nach dem Anlegen der `CLAUDE.md` suchte `local-fast`
  die Aufgabendateien im Projektordner (3 von 9 Läufen fehlgeschlagen). Der Arbeitsordner
  liegt jetzt in `E:\LlamaCpp\bench-work` (`workDir` in `config\benchmark.json`), der Lauf
  wurde wiederholt.
- **`timeout` in Git Bash beendet Claude Code nicht mit.** Von Hand gestartete Testläufe
  liefen nach dem Abbruch weiter und belegten das Modell. Folge: `model limit reached` beim
  Wechsel, weil der Server ein benutztes Modell nicht entlädt. Ein Versuch mit einer
  zweiten Chat-Vorlage für `local-fast` ist dadurch nicht auswertbar und wurde verworfen.
  Das Benchmark-Skript ist nicht betroffen (`taskkill /T`).
- **Lokal angelegte Ollama-Modelle** (`ollama create`) stehen nicht im alten
  Manifest-Ordner. `Add-Model.ps1 -FromOllama` findet nur geladene Modelle; für die anderen
  den Blob mit `-Path` angeben.

### Offen

- **`local-fast` läuft über llama.cpp nach der Lösung weiter** (ruft `ReportFindings`,
  Memory-Notizen, `Skill` auf, bis zu 56 Runden). Über Ollama am selben Tag nicht (ein Lauf).
  Ursache ungeklärt.
- **Continue in VS Code nicht geprüft.** Die neue Konfiguration ist installiert
  (`Install-Continue.ps1`, alte Datei gesichert als `config.yaml.bak-20261114-172513`), die
  Bedienung in VS Code aber nicht ausprobiert. Der Server startet nicht von selbst mit
  Windows; für Continue vorher `Start-Server.ps1` oder `claude-local` ausführen.
- **`/model` in einer interaktiven Sitzung** weiter ungeprüft, ebenso Hintergrundanfragen
  nach einem Wechsel.
- **Ollama ist weiter installiert** samt Modellen (etwa 100 GB) und Umgebungsvariablen. Für
  dieses Projekt wird es nicht mehr gebraucht; entfernt wird es nur auf ausdrücklichen Wunsch.
- Einzelne Wirkung von GPU-Aufteilung, Arbeitsregeln, Denkaufwand und MTP-Länge messen.
- Schwerere Benchmark-Aufgaben.
- Ablehnungsraten weiter nur laut Modellkarten.

## 2026-11-14: Wiederholungsmessung der unzensierten Modelle

### Durchgeführt

`Benchmark-Models.ps1 -Only "unc-*" -Label repeat3 -Repeat 3`: `unc-heretic`, `unc-blackfrost`
und `unc-coletti` bei 64k Kontext, jede Agenten-Aufgabe dreimal.

### Ergebnis

- Alle drei Modelle bestanden 9 von 9 Läufen, kein Lauf überschritt das Zeitlimit.
- Zeit je Durchgang: `unc-heretic` 350 / 334 / 309 s, `unc-coletti` 363 / 263 / 389 s,
  `unc-blackfrost` 706 / 638 / 331 s.
- Die Rangfolge vom 13.11. (Blackfrost am schnellsten, Heretic am langsamsten) hat sich nicht
  bestätigt. Die Streuung zwischen den Läufen ist größer als der Abstand zwischen den Modellen.
  Auswertung: [modellwahl.md](modellwahl.md), Abschnitt „Wiederholungsmessung“.

### Umstellung und Aufräumen

- `local-coder` beruht jetzt auf `unc-heretic` (`modelfiles\local-coder.Modelfile`, neu gebaut).
  `Test-Model.ps1`: 54,9 Tok./s, Tool-Call in Ordnung, 100 % GPU.
- Gelöscht: `unc-blackfrost`, `unc-coletti`, `local-legacy` mit dem Basismodell
  `mgraffam/qwen3.8-EfficientThink-uncensored:27b` sowie die drei GGUF-Dateien unter
  `E:\Ollama\import\`. Auf Laufwerk E: sind dadurch 97 GB frei geworden (179 → 276 GB frei).
- Profil `local-legacy` und Kurzname `alt` entfernt. Die gelöschten Modelle stehen weiter in
  `config\benchmark.json`; das Benchmark-Skript überspringt nicht installierte Modelle.

### Modellwechsel in der Sitzung (`/model`)

- `claude-local` übergibt Claude Code die Einstellung `modelPicker` über eine Datei nur für
  diesen Start (`--settings`, Datei `%TEMP%\claude-local-settings.json`). Die Auswahl von
  `/model` zeigt damit die Profile aus `picker` in `config\agent.json` statt der
  Anthropic-Modelle. Der normale Befehl `claude` ist nicht betroffen.
- `CLAUDE_CODE_SUBAGENT_MODEL` wird nicht mehr gesetzt, damit Subagenten nach einem Wechsel dem
  Hauptmodell folgen.
- Das Kontextfenster gilt für die ganze Sitzung; bei mehreren Modellen zählt das kleinste.
- Geprüft: Start mit beiden Modellen über `-p`, die erzeugte Einstellungsdatei. Nicht geprüft:
  die Auswahl selbst in einer interaktiven Sitzung.
- Offen: Hintergrundanfragen („haiku“) gehen weiter an das Startmodell. In einem Lauf mit `-p`
  gab es keine; ob eine interaktive Sitzung nach dem Wechsel welche schickt und Ollama dann
  umlädt, ist nicht gemessen.

### Offen

- Ablehnungsraten weiter nur laut Modellkarten, nicht selbst geprüft.
- Kontextlänge in der Ollama-App steht weiter auf 262144 (betrifft nur Modelle ohne Profil).
- Optional: modellabhängige GPU-Aufteilung (70:30 für MTP-Modelle).

## 2026-11-13 nachts: GPU-Aufteilung, unzensierte Modelle mit MTP, GitHub

### Durchgeführt

1. **Modellwechsel:** Profil `local-fast` (`qwen3-coder:30b`), Kurznamen in `config\agent.json`
   (`claude-local -Model schnell|unzensiert|alt`), beide Chat-Modelle in Continue.
2. **Datenschutz:** In VS Code `continue.telemetryEnabled` und `continue.enableNextEdit` aus,
   in Ollama `OLLAMA_NO_CLOUD=1`.
3. **GPU-Aufteilung gemessen** (`scripts\Measure-GpuSetups.ps1`, 14 Setups). Ergebnis:
   PCIe 4.0 x4 der 3060 bremst bei der Aufteilung nach Schichten nicht, die 3060 selbst schon.
   `LLAMA_ARG_TENSOR_SPLIT=65,35` eingestellt. Details: [gpu-tuning.md](gpu-tuning.md).
4. **MTP entdeckt:** Das offizielle `qwen3.8:27b` ist mit MTP doppelt so schnell. Dem bisherigen
   unzensierten Modell fehlen die MTP-Schichten. Drei unzensierte Varianten mit MTP von
   Hugging Face geladen (`E:\Ollama\import\`), mit `scripts\Import-Gguf.ps1` importiert, alle
   bestanden den Benchmark mit 3 / 3.
5. **Standardmodell gewechselt:** `local-coder` beruht jetzt auf `unc-blackfrost`, etwa 55 statt
   25 Tok./s. Das alte Modell bleibt als `local-legacy`. Ende-zu-Ende-Test mit `claude-local`:
   Datei richtig angelegt und ausgeführt, MTP aktiv.
6. **Git:** Repository angelegt und nach GitHub gepusht (privat: `MD220411/Unzensiert`).

### Fehler und Erkenntnisse

- **Messskript hing zwei Stunden.** `ConvertTo-Json` in Windows PowerShell 5.1 serialisierte
  versteckte Eigenschaften von `Get-Content`-Zeilen (PSProvider) und kam nicht zum Ende.
  Behoben mit `[string]`-Umwandlung.
- **Messskript verlor `num_ctx`.** Die Hilfsfunktion las bei einer Hashtable deren Eigenschaften
  statt der Einträge. Ollama lud `qwen3.8:27b` deshalb mit dem 262k-Kontext der App, teils auf
  der CPU, mit 14 statt 60 Tok./s. Behoben, betroffene Werte neu gemessen. Das Skript erkennt
  jetzt Nachladungen.
- **Ollama meldet „100 % GPU“, auch wenn Schichten im Arbeitsspeicher liegen.**
- **`CUDA_VISIBLE_DEVICES` allein blendet keine Karte aus:** Ollama findet sie dann über Vulkan.
  Für Einzelkarten-Tests zusätzlich `OLLAMA_VULKAN=0`.
- **Der erste Download brach ab** (Verbindung hing 30 Minuten). Das Download-Skript bricht bei
  Stillstand ab und setzt fort.

### Offen

- Die GGUF-Dateien unter `E:\Ollama\import\` (51 GB) sind nach dem Import doppelt vorhanden und
  können gelöscht werden. Ebenso `unc-heretic`, `unc-coletti` und `local-legacy` mit dem
  Basismodell, falls nicht mehr gebraucht (je 17 bis 19 GB).
- Kontextlänge in der Ollama-App steht weiter auf 262144 (betrifft nur Modelle ohne Profil).
- Ablehnungsraten der unzensierten Modelle nur laut Modellkarten, nicht selbst geprüft.
- Wiederholungsmessung (`-Repeat 3`) für eine belastbare Rangfolge der unzensierten Modelle.

## 2026-11-13 abends: Phase 5 abgeschlossen, Benchmark ausgewertet

### Autocomplete geprüft

`Restart-Ollama.ps1` und `Install-Continue.ps1` ausgeführt, `qwen2.5-coder:1.5b-base` geladen
(Fähigkeiten laut Ollama: `completion, insert`). Test mit derselben Anfrage, die Continue schickt:

| Prüfung | Ergebnis |
|---|---|
| `local-coder` zuerst geladen, dann Autocomplete | beide 100 % GPU |
| Autocomplete zuerst geladen, dann `local-coder` | beide 100 % GPU |
| VRAM belegt | 5070 Ti 13,4 von 16,3 GB, 3060 10,5 von 12,3 GB |
| Antwortzeit FIM (warm) | 0,15 s |
| Ergebnis | `is_prime` korrekt ergänzt |

`Install-Continue.ps1` lädt das Modell jetzt über die API statt über `ollama pull`, weil die
Fortschrittsbalken die Ausgabe mit Steuerzeichen füllten.

### Benchmark

Lauf 15:25 bis 17:12, alle 12 Kombinationen gemessen. Bewertung in [modellwahl.md](modellwahl.md).
Kern: Nur drei Modelle lösen alle Aufgaben, alle drei nur mit 64k. `qwen3-coder:30b` ist dabei
dreimal so schnell wie `local-coder`. Jede Aufgabe lief nur einmal, eine Wiederholungsmessung
steht aus.

## 2026-11-13 nachmittags: Phase 5, Autocomplete

### Durchgeführt

1. VS-Code-Erweiterung Continue 2.0.0 installiert. Vergleich mit llama.vscode und Twinny:
   Continue gewählt, weil es neben dem Autocomplete auch einen Chat mit `local-coder` bietet.
2. `config\continue.config.yaml` angelegt: Chat mit `local-coder`, Autocomplete mit
   `qwen2.5-coder:1.5b-base`. Diese Base-Variante ist für das Ergänzen in der Mitte (FIM)
   trainiert. Mit `scripts\Install-Continue.ps1` nach `%USERPROFILE%\.continue\config.yaml`
   kopiert.
3. `OLLAMA_MAX_LOADED_MODELS` von 1 auf 2 gesetzt (Benutzer-Umgebung). Wirksam erst nach
   `Restart-Ollama.ps1`, das wegen des laufenden Benchmarks noch aussteht.

### Erkenntnisse aus dem Quellcode von Continue 2.0.0

- Continue liest `num_ctx` über `/api/show` aus dem Ollama-Profil, solange in der
  Konfiguration kein `contextLength` steht. Für `local-coder` schickt es deshalb 65536. Ein
  abweichender Wert würde Ollama bei jedem Wechsel zwischen `claude-local` und Continue das
  Modell neu laden lassen. Modelle ohne `num_ctx` bekommen von Continue 8192.
- Für FIM schickt Continue Text vor und hinter dem Cursor als `prompt` und `suffix` an
  `/api/generate`. Die Vorlage des Ollama-Modells baut daraus den FIM-Prompt. Ein eigenes
  Profil ist für das Autocomplete-Modell deshalb nicht nötig.
- `keep_alive` setzt Continue selbst auf 30 Minuten.


## 2026-11-13 nachmittags: Modellvergleich

### Durchgeführt

1. `scripts\Benchmark-Models.ps1` gebaut: Rohwerte (Laden, Tempo, Tool-Calls, Denken) und drei
   Agenten-Aufgaben über `claude-local` (`benchmark\tasks\`: bugfix, feature, multifile).
2. Erster Lauf 14:23–14:48: `qwen38-unc-64k` vollständig (3 / 3 bestanden). Bei
   `qwen38-unc-32k` wurde der Lauf während der dritten Aufgabe abgebrochen, weil die Sitzung endete.
3. Lauf ab 15:25 fortgesetzt, Ausgabe in `logs\benchmark\run-20261113-1525.log`.
   `flint:40b` ist nicht installiert und wird übersprungen.
4. Altbestand `%USERPROFILE%\.ollama\models` ist gelöscht, `C:` hat 185,4 GB frei.

### Fehler und Erkenntnisse

- **32k Kontext reicht für Claude Code kaum.** Bei `qwen38-unc-32k` meldete Claude Code in der
  bugfix-Aufgabe „Autocompact is thrashing“: Der Kontext lief innerhalb von drei Runden wieder voll.
  Der Lauf dauerte 415 s bei einem Limit von 420 s, die feature-Aufgabe lief ins Zeitlimit.
  Systemprompt und Tool-Beschreibungen von Claude Code belegen allein schon einen großen Teil.
- **Der Bericht zählte Läufe mit überschrittenem Zeitlimit als bestanden**, wenn die Dateien
  zufällig schon stimmten. Behoben: Solche Läufe zählen jetzt als nicht bestanden und erscheinen
  als `Zeit, Dateien ok`.

## 2026-11-13: Phasen 1 bis 3 (Backend, Modell, Agent)

### Ausgangslage

- RTX 5070 Ti (16 GB) und RTX 3060 (12 GB), i9-14900K, 128 GB RAM
- Ollama 0.40.9, vier Modelle, Modellordner laut App-Einstellung `%USERPROFILE%`
- `C:` mit 56,7 GB frei

### Durchgeführt

1. Projektstruktur angelegt (`config`, `modelfiles`, `scripts`, `bin`, `docs`).
2. Umgebungsvariablen aus `config\ollama.env.json` gesetzt.
3. Ollama von 0.40.9 auf 0.40.16 aktualisiert (Signatur des Installers geprüft).
4. Modellbestand (58,4 GB: `blobs`, `manifests`, `manifests-v2`) von `%USERPROFILE%` nach
   `E:\Ollama\models` kopiert, Datei für Datei geprüft, Quelle danach gelöscht.
   `C:` hat jetzt 112,7 GB frei.
5. Modellordner in den Einstellungen der Ollama-App auf `E:\Ollama\models` gestellt.
   Sicherung der App-Datenbank: `%LOCALAPPDATA%\Ollama\backup-20261113-140928\`.
6. Profil `local-coder` gebaut und gemessen.
7. Starter `claude-local` angelegt, `bin\` in den Benutzer-PATH aufgenommen.

### Messwerte `local-coder`

| Kontext | VRAM gesamt | Platzierung | Tempo | Tool-Calls |
|---|---|---|---|---|
| 32768 | 21 GB | 100 % GPU | 23,8 Tokens/s | OK |
| 65536 | 22 GB | 100 % GPU | 24,2 Tokens/s | OK |

Bei 64k sind auf der 5070 Ti etwa 0,6 GB und auf der 3060 etwa 3 GB frei. Gewählt: 64k.

### Ende-zu-Ende-Tests mit `claude-local`

| Aufgabe | Ergebnis | Dauer |
|---|---|---|
| Datei `fizzbuzz.py` anlegen | korrekt, läuft | 26 s |
| Datei lesen, ändern, mit Python ausführen, Ausgabe melden | korrekt | 36 s |

### Fehler und Erkenntnisse

- **Falscher Ordner kopiert.** Zuerst wurde der Standardordner
  `%USERPROFILE%\.ollama\models` (71,7 GB) kopiert. Der war ein Altbestand. Der echte
  Bestand lag wegen der App-Einstellung direkt in `%USERPROFILE%`. Die falsche Kopie auf
  `E:` wurde gelöscht, die Quelle blieb unberührt. Folge für das Skript:
  `Move-OllamaModels.ps1` verlangt jetzt `-Source` ausdrücklich und fasst nur `blobs` und
  `manifests*` an.
- **Die Ollama-App überstimmt `OLLAMA_MODELS` und `OLLAMA_CONTEXT_LENGTH`.** Details in
  [einrichtung.md](einrichtung.md).
- **Das Basismodell bringt `num_ctx 262144` mit.** Deshalb das eigene Profil.
- **`Start-Process -Wait` hängt beim Ollama-Installer**, weil es auch auf den vom
  Installer gestarteten Ollama-Prozess wartet. In `Update-Ollama.ps1` behoben.
- **Claude Code nimmt für unbekannte Modellnamen 1 Mio. Tokens Kontext an.** Behoben über
  `CLAUDE_CODE_MAX_CONTEXT_TOKENS` im Starter.
- **PowerShell bindet Flags wie `-p` an eigene Parameter.** Der Starter wertet `$args`
  deshalb von Hand aus.

### Offen

- ~~Altbestand `%USERPROFILE%\.ollama\models` (71,7 GB) löschen.~~ Erledigt, siehe oben.
- Kontextlänge in der Ollama-App steht weiter auf 262144.
- Noch nicht getestet: lange Sitzungen mit Komprimierung, große Projekte, Verhalten bei
  belegtem VRAM durch andere Programme.
- Phase 4 (Roo Code oder Cline als Ausweichlösung) war nicht nötig.
- ~~Phase 5 (Autocomplete mit kleinem Modell).~~ Erledigt, siehe oben.

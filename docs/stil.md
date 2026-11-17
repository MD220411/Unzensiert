# Erscheinungsbild „Nachtschicht“

Ein gemeinsames Aussehen für die Kommandozeile, für Claude Code und für `claude-local`.
Alle Farben, Zeichen und Texte stehen in `config\style.json`; angewendet werden sie mit
`scripts\Install-Style.ps1`.

## Die Idee

Eine Werkstatt bei Nacht: dunkler, leicht bläulicher Grund, warmes Schriftweiß wie Papier
unter einer Lampe, Messing als Akzent. Darin gibt es zwei Lichtquellen, und die
**Farbtemperatur zeigt, wo gerade gerechnet wird**:

| Stimmung | Wann | Licht | Zeichen |
|---|---|---|---|
| **Werkbank** | die Shell | neutral dunkel, Messing `#E9B44C` | `»` |
| **Glut** | `claude-local`: das Modell läuft auf den eigenen Grafikkarten | warm, Rußschwarz mit Glutorange `#FF8A3D` | `●` |
| **Fernlicht** | `claude`: das Modell läuft in der Cloud | kühl, Nachtblau mit Eisblau `#9CC4E4` | `◇` |

Startet eine Sitzung, wechselt das ganze Fenster die Stimmung (Hintergrund, Schrift,
Cursor) und kehrt beim Beenden zur Werkbank zurück. Warm heißt: hier, auf der eigenen
Maschine. Deshalb bleiben auch im kühlen Fernlicht die Rückfragen um Erlaubnis und die
Bash-Eingabe warm gefärbt: Dort passiert etwas auf dem eigenen Rechner.

Wiederkehrende Elemente:

- **Der Glutpunkt** `●` steht vorn in der Eingabezeile und leuchtet, solange
  `llama-server` läuft. Ist der Server aus, steht dort ein blasser Ring `○`. Derselbe
  Punkt ist das Symbol des Tabs.
- **Messlinien** `━━━━━━━━` statt Balken oder Prozentzahlen allein: Speicher der beiden
  Grafikkarten, Füllstand des Kontexts, Verbrauch des 5-Stunden-Limits.
- **Gemessenes steht da.** Die Eingabezeile zeigt die Dauer des letzten Befehls (ab 2 s)
  und die Uhrzeit, die Statuszeile die tatsächliche Belegung.
- **Deutsche Typografie:** Guillemet `»` als Eingabezeichen, Zahlen mit Komma, Wortlaut
  der Wartetexte aus der Werkstatt („Misst nach“, „Feilt“, „Schürt die Glut“).

## Was wo zu sehen ist

**Shell** (Profil „Nachtschicht“ in Windows Terminal, `scripts\style\Shell.ps1`):

```
  N A C H T S C H I C H T                          Samstag, 14. November · 23:52

  RTX 5070 Ti   ━━━━━━━━━━━━━━━━   14,5 / 15,9 GB   40 °C
  RTX 3060      ━━━━━━━━━━━━━━━━    7,4 / 12,0 GB   59 °C

  ● Die Glut brennt seit 23:50 Uhr.

 ● Unzensiert  E:\Projekte  ·  main ±6 ↑1                          3,2 s · 23:52
 » 
```

Zeile 1: Glutpunkt, Ordner (hell, wie ein Titel), Weg dorthin (blass), Git-Zweig mit Zahl
der geänderten Dateien und Vorsprung; rechts Dauer des letzten Befehls und Uhrzeit.
Zeile 2: `»`, nach einem fehlgeschlagenen Befehl rot (dazu rechts „Ende 1“ mit dem
Rückgabewert). Als Administrator steht `ADMIN` in Rot in Zeile 1.

**Claude Code** (beide Stimmungen): eigenes Farbthema, deutsche Wartetexte und eine
Statuszeile (`scripts\style\Statusline.ps1`):

```
 ◇ Fernlicht  Fable 5.2  ·  Kontext ━━━━━━━━ 23 %  ·  5-h-Limit ━━━━━━━━ 81 % bis 01:00  ·  Unzensiert main ±6
 ● Glut  local-coder  ·  Kontext ━━━━━━━━ 92 %  ·  5070 Ti ━━━━━━━━ 14,5 GB  ·  3060 ━━━━━━━━ 7,4 GB  ·  Unzensiert main ±6
```

Die Kontextlinie wird ab 70 % gelb und ab 90 % rot. In lokalen Sitzungen liest die
Statuszeile die Grafikkarten alle 5 Sekunden neu.

**`claude-local`** meldet sich vor dem Start in Glutfarben:

```
 ● Glut  local-coder  ·  Kontext 57.600 von 64.000 Tokens  ·  http://127.0.0.1:8080
   /model wechselt zwischen local-coder, local-fast, local-qwen38
```

Ist die Ausgabe umgeleitet (Benchmark, Skripte), erscheinen stattdessen die bisherigen
schlichten Zeilen `claude-local: model ...` ohne Farbcodes.

## Einrichten

```
powershell -ExecutionPolicy Bypass -File scripts\Install-Font.ps1     # einmalig: Schrift IBM Plex Mono
powershell -ExecutionPolicy Bypass -File scripts\Install-Style.ps1    # anwenden, nach jeder Änderung wiederholen
```

Danach einen neuen Tab in Windows Terminal öffnen. Laufende Claude-Code-Sitzungen
übernehmen das Thema beim nächsten Start.

`Install-Font.ps1` lädt IBM Plex Mono (SIL Open Font License) und installiert sie nur für
den angemeldeten Benutzer, ohne Administratorrechte.

`Install-Style.ps1` ändert:

| Ort | Was |
|---|---|
| `settings.json` von Windows Terminal | Farbschema und Fensterthema „Nachtschicht“; unter `profiles.defaults` Schrift, Abstand, Cursor; neues Profil „Nachtschicht“ als Standardprofil. Die vorhandenen Profile bleiben erhalten. |
| `%USERPROFILE%\.claude\themes\` | `nachtschicht-glut.json`, `nachtschicht-fernlicht.json` |
| `%USERPROFILE%\.claude\settings.json` | `theme` (Fernlicht), `statusLine`, `spinnerVerbs` |
| `%LOCALAPPDATA%\Nachtschicht\glut.png` | das Tab-Symbol, vom Skript gezeichnet |

Vor der ersten Änderung wird jede Einstellungsdatei einmal nach
`<Name>.vor-nachtschicht` kopiert. Schalter:

- `-PreviewDir <Ordner>` schreibt die Ergebnisse in einen Ordner, statt etwas zu ändern.
- `-Remove` nimmt genau die eigenen Einträge wieder heraus; alles andere in den Dateien
  bleibt, wie es ist. Die Schrift bleibt installiert.

Das Profil „Nachtschicht“ startet PowerShell mit `-ExecutionPolicy RemoteSigned` nur für
diesen Prozess. Die Ausführungsrichtlinie des Systems wird nicht verändert, und es wird
kein PowerShell-Profil unter `Dokumente` angelegt.

## Anpassen

Alles in `config\style.json`, danach `scripts\Install-Style.ps1`:

| Abschnitt | Inhalt |
|---|---|
| `modes` | je Stimmung: Hintergrund, Schrift, Cursor, Akzent, blasse Töne, Zeichen, Name |
| `ink` | Bedeutungsfarben: in Ordnung, Warnung, Fehler, Glut, Git-Zweig |
| `palette` | die 16 ANSI-Farben des Terminals |
| `glyphs`, `texts` | Zeichen und deutsche Texte von Eingabezeile, Begrüßung und Statuszeile |
| `font` | Schrift, Größe, Zeilenhöhe, Quelle für `Install-Font.ps1` |
| `terminal` | Abstand, Cursorform, Farbe der Tab-Leiste und des Fensterrahmens |
| `shell` | Begrüßung an/aus (`greeting`), ab wann die Dauer erscheint, Farben der Eingabe |
| `claude` | Themen für Claude Code (`themes`), Wartetexte (`spinnerVerbs`), Schwellen der Statuszeile |

Änderungen an Eingabezeile, Begrüßung und Statuszeile wirken sofort im nächsten Tab oder
beim nächsten Aufruf, weil die Skripte `style.json` bei jedem Start lesen. Nur für
Windows Terminal und die Dateien von Claude Code muss `Install-Style.ps1` erneut laufen.

Die Schlüssel unter `claude.themes.*.overrides` sind die Farbnamen von Claude Code
(`claude`, `text`, `permission`, `diffAdded` ...). Unbekannte Namen ignoriert Claude Code
stillschweigend.

## Aufbau

```
config\style.json            einzige Quelle für Farben, Zeichen, Texte
scripts\lib\Style.ps1        Bausteine: Farben, Tönen des Terminals, Messwerte (Karten, Git, Server)
scripts\style\Shell.ps1      richtet die interaktive Shell ein (Eingabezeile, Begrüßung, Funktion claude)
scripts\style\Statusline.ps1 Statuszeile von Claude Code
scripts\Install-Style.ps1    wendet style.json auf Windows Terminal und Claude Code an
scripts\Install-Font.ps1     installiert die Schrift
```

`lib\Style.ps1` liest `style.json` selbst und nicht über `lib\Config.ps1`: Shell und
Statuszeile laden nur diese eine Datei, damit sie schnell starten und
`$ErrorActionPreference = 'Stop'` aus `_common.ps1` nicht in die interaktive Shell gerät.

So kommt die Stimmung zustande:

- **Tönen des Fensters:** `Set-TerminalPalette` schickt die Steuerfolgen OSC 10, 11 und 12
  (Schrift, Hintergrund, Cursor). Das geschieht nur in Windows Terminal, nur wenn das
  Aussehen installiert ist und nur, wenn die Ausgabe nicht umgeleitet ist.
- **`claude` in der Shell** ist eine Funktion, die das Fenster auf Fernlicht stellt,
  `claude.exe` mit allen Argumenten startet und danach zur Werkbank zurückkehrt.
- **`claude-local`** setzt die Variable `NACHTSCHICHT_MODE=glut`, stellt das Fenster auf
  Glut und übergibt für diesen Start das Thema `custom:nachtschicht-glut` und die
  Statuszeile mit 5-Sekunden-Takt (`Get-LocalLookSettings`). Die Statuszeile erkennt an
  der Variable, ob sie Grafikkarten oder das Limit zeigt.

## Gemessen und nicht gemessen

Gemessen am 2026-11-14 (Windows PowerShell 5.1):

| | Dauer |
|---|---|
| Start der Shell mit Begrüßung | etwa 440 ms (PowerShell allein: 134 ms) |
| eine Eingabezeile, in einem Git-Ordner | etwa 30 ms |
| ein Lauf der Statuszeile | etwa 380 ms |
| `nvidia-smi`-Abfrage beider Karten | etwa 60 ms |

Geprüft: Alle Skripte laufen fehlerfrei, die erzeugten JSON-Dateien sind gültig, ein
zweiter Lauf von `Install-Style.ps1` ändert nichts mehr, die Steuerfolgen und die Texte
von Eingabezeile, Statuszeile und Startmeldung stimmen.

**Nicht geprüft**, weil das Einrichten ohne Blick auf den Bildschirm geschah: wie es im
Fenster tatsächlich aussieht. Offen sind vor allem die Farbwirkung im Zusammenspiel, das
Schriftbild von IBM Plex Mono bei 11 pt, ob Windows Terminal den Hintergrund beim Start
einer Sitzung sichtbar umstellt und ob Claude Code beide Themen ohne Meldung annimmt.

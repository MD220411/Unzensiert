# Erscheinungsbild

Ein gemeinsames Aussehen für die Kommandozeile, für Claude Code und für `claude-local`. Es
gibt zwei Stile; welcher gilt, steht in `config\style.json`:

| Stil | Charakter | Datei |
|---|---|---|
| **Ausbruch** (aktiv) | bunt, frei, laut: Bilder aus farbigen Zeichen statt aus Pixeln | `config\styles\ausbruch.json` |
| **Nachtschicht** | ruhig, warm: eine Werkstatt bei Nacht | `config\styles\nachtschicht.json` |

Alle Farben, Zeichen und Texte stehen in der Datei des Stils; angewendet wird er mit
`scripts\Install-Style.ps1`.

## Stil wechseln

In `config\style.json` den Wert von `active` ändern (`"ausbruch"` oder
`"nachtschicht"`), dann:

```
powershell -ExecutionPolicy Bypass -File scripts\Install-Style.ps1
```

Das Skript nimmt die Einträge aller bekannten Stile heraus und schreibt nur den aktiven
hinein: Farbschema, Fensterthema und Profil in Windows Terminal werden ersetzt, die
Themen-Dateien des alten Stils unter `%USERPROFILE%\.claude\themes\` gelöscht. Danach
einen neuen Tab öffnen.

## „Ausbruch“

### Die Idee

Freiheit sieht man an der Farbe. Das lokale Modell läuft ohne Leine auf den eigenen
Karten, und dieser Stil zeigt das so, wie man an eine Wand sprüht: Bilder aus bunten
Buchstaben und Zeichen statt aus Pixeln. Die Zeichen bleiben nicht in ihren Buchstaben;
sie brechen aus und fliegen davon.

Die **Menge der Farbe zeigt, wo gerechnet wird**:

| Stimmung | Wann | Licht | Zeichen |
|---|---|---|---|
| **Straße** | die Shell | fast schwarz mit Violett, Pink `#FF3D9A`, Cursor Säuregelb | `✦` |
| **Frei** | `claude-local`: das Modell läuft auf den eigenen Grafikkarten | der ganze Farbkreis, Name „Unzensiert“ in Regenbogenfarben | `✦` |
| **Wolke** | `claude`: das Modell läuft in der Cloud | Nachtblau, nur eine Farbe: Cyan `#2EE6E6` | `◇` |

Der Farbkreis: Pink `#FF3D9A`, Orange `#FF8A1F`, Gelb `#FFE03D`, Limette `#8CFF3D`,
Cyan `#2EE6E6`, Blau `#4D8DFF`, Violett `#B45CFF`. Zwischen zwei Farben wird stufenlos
gemischt, nach Violett geht es wieder bei Pink weiter. Auch in der Wolke bleiben die
Rückfragen um Erlaubnis und die Bash-Eingabe pink: Dort passiert etwas auf dem eigenen
Rechner.

Wiederkehrende Elemente:

- **Das Bild aus Zeichen.** Ein Wort wird in einer Blockschrift gesetzt, jeder Block mit
  einem zufälligen Buchstaben oder Zeichen gefüllt (`UNZESIRT#@%&$WMXKB08`) und schräg
  durch den Farbkreis gefärbt. Um die Buchstaben liegt Sprühnebel aus leichten Zeichen
  (`.,:;'~*+^`), der letzte Buchstabe bröckelt, und rechts brechen Zeichen aus und
  fliegen davon: erst dichte, dann `+*=~^%<>/\`, am Ende nur noch Punkte und Striche,
  immer blasser. Jedes Bild ist anders; auch die Farben beginnen jedes Mal an einer
  anderen Stelle des Kreises.
- **Gesprühte Messlinien** statt Balken: Der gefüllte Teil besteht aus zufälligen
  Zeichen (`#%&@$*+=WMX`) und läuft durch den Farbkreis, eine volle Linie zeigt alle
  Farben. Der leere Rest ist eine blasse Punktreihe `········`. Ab 70 % Kontext wird die
  Linie gelb, ab 90 % rot.
- **Die Eingabezeile wechselt.** Der Ordnername steht Buchstabe für Buchstabe in
  Regenbogenfarben und dreht sich nach jedem Befehl ein Stück weiter. Das Eingabezeichen
  ist jedes Mal ein anderes (`» › ! ? # * & % ~ @ ^ $`) in der nächsten Farbe des Kreises;
  nach einem fehlgeschlagenen Befehl ist es rot.
- **Rebellische Wartetexte:** „Sprüht“, „Bricht aus“, „Malt über den Rand“, „Pfeift auf
  Schablonen“, „Sprengt die Ketten“, „Tanzt aus der Reihe“ …

### Was wo zu sehen ist

**Shell** (Profil „Ausbruch“ in Windows Terminal), hier ohne Farben:

```
  '                        ,                                                 ~            `      .              ;
  #$     'WZ  X0.    +XB  UUU@Z%RRNE  B0RUZZB%ZT  8E      8X    $#&0B0TK* MSE@NX  0WWE%@8U#@; UR#IEIZ8    NS0UB08EI%     ^ <:
  MT      MT: IW0$    Z&      ` BS   .EB     ^   '@&RE    $X  B&            ZN+   R8   ~ *+   %&   :^ MS    ' IB    TTR    =
  XI      @S  E%  M$  MK      WB      I8SWM0UI~   0M  #8  #M   ^W8ENZT      0@    XIR#$8EK;  ^WR@&W0SI        E+:   @ & *
  BX      ZW  SS:   %ZI@    Z#       `IX ;  ^     RM    KI#R   :      Z$    ZE    %0       ;  EX.+  SX        @%*   R U   =
  : E%WB#$+   %B      M%.'SSZR%ZX&8T  @KIT@@#0%@` KR      8U  0R&%B%RR    &0R0RN  Z0ME&8MXE$; ZB      BS      K8       %  %
               *                   ,  '                         ~          '      +

  frei · lokal · unzensiert · bunt                                              Dienstag, 17. November · 17:15

  RTX 5070 Ti   #$*X%*$XXX@@$M#·   15,2 / 15,9 GB   37 °C
  RTX 3060      $&*=*=X@&W=$#@··   10,1 / 12,0 GB   27 °C

  ✦ Frei seit 14:43 Uhr. Das Modell rechnet auf deinen eigenen Karten.

 ✦ Unzensiert  E:\Projekte  ·  main ±10                                                                     17:15
 &
```

Das große Bild braucht etwa 117 Spalten. In schmaleren Fenstern wird es in halber Breite
gesetzt (mit weniger Sprühnebel), unter etwa 60 Spalten fällt es weg. Ist der Server aus,
steht statt `✦ Frei seit …` ein blasser Stern `✧ Noch still. claude-local lässt es los.`

**`claude-local`** beginnt jede Sitzung mit einem eigenen Bild, **FREI**:

```
          ^   .   +  +          .  ;        8   %              ^
  UZN%K0Z%WT ^N@XRZNBZ   :&KE#S#U8S8 ~I&I#0/  Z   N ^  >*   =
  B0          %B      TB;^&I~  ~  *     NZ   X    U        *       ,
  8@K$8#$B'   XX%%NU%Z    B$%R0ZKS      TX   K                      °
  M0         *B&~   EI*   UM          ' X^    W  8I              =   ,
  %S          8S      %$  8$TU#WUNI@ ;SRWEW<; B#    /             .    :
                          + , :,        .  ,         ^

 ✦ Unzensiert  local-coder  ·  Kontext 57.600 von 64.000 Tokens  ·  http://127.0.0.1:8080
   /model wechselt zwischen local-coder, local-fast, local-qwen38
```

**Claude Code**: eigenes Farbthema je Stimmung („Ausbruch · Frei“, „Ausbruch · Wolke“),
die Wartetexte und die Statuszeile:

```
 ✦ Unzensiert  local-coder  ·  Kontext =+&%#··· 63 %  ·  5070 Ti &%#&W*=  15,2 GB  ·  3060 $W=MM$M· 10,1 GB  ·  Unzensiert main ±10
 ◇ Wolke  Fable 5.2  ·  Kontext =@$@XM$· 93 %  ·  5-h-Limit $#%@+*·· 81 % bis 02:00  ·  Unzensiert main ±10
```

Das Tab-Symbol ist ein Farbrad aus allen Farben des Kreises.

## „Nachtschicht“

Eine Werkstatt bei Nacht: dunkler, leicht bläulicher Grund, warmes Schriftweiß wie Papier
unter einer Lampe, Messing als Akzent. Die **Farbtemperatur zeigt, wo gerade gerechnet
wird**:

| Stimmung | Wann | Licht | Zeichen |
|---|---|---|---|
| **Werkbank** | die Shell | neutral dunkel, Messing `#E9B44C` | `»` |
| **Glut** | `claude-local` | warm, Rußschwarz mit Glutorange `#FF8A3D` | `●` |
| **Fernlicht** | `claude` | kühl, Nachtblau mit Eisblau `#9CC4E4` | `◇` |

Der Glutpunkt `●` vorn in der Eingabezeile leuchtet, solange `llama-server` läuft (sonst
ein blasser Ring `○`). Messlinien `━━━━━━━━` zeigen Speicher der Karten, Kontext und
5-Stunden-Limit, die Wartetexte kommen aus der Werkstatt („Misst nach“, „Feilt“, „Schürt
die Glut“).

```
  N A C H T S C H I C H T                          Samstag, 14. November · 23:52

  RTX 5070 Ti   ━━━━━━━━━━━━━━━━   14,5 / 15,9 GB   40 °C
  RTX 3060      ━━━━━━━━━━━━━━━━    7,4 / 12,0 GB   59 °C

  ● Die Glut brennt seit 23:50 Uhr.

 ● Unzensiert  E:\Projekte  ·  main ±6 ↑1                          3,2 s · 23:52
 »
```

## Gemeinsam in beiden Stilen

Startet eine Sitzung, wechselt das ganze Fenster die Stimmung (Hintergrund, Schrift,
Cursor) und kehrt beim Beenden zur Stimmung der Shell zurück. Die Eingabezeile zeigt
Ordner, Weg dorthin, Git-Zweig mit Zahl der geänderten Dateien und Vorsprung, rechts die
Dauer des letzten Befehls (ab 2 s) und die Uhrzeit; nach einem Fehler rechts „Ende 1“ mit
dem Rückgabewert, als Administrator `ADMIN` in Rot. Die Statuszeile liest in lokalen
Sitzungen die Grafikkarten alle 5 Sekunden neu.

Ist die Ausgabe umgeleitet (Benchmark, Skripte) oder der Stil nicht installiert, gibt
`claude-local` stattdessen die schlichten Zeilen `claude-local: model ...` ohne Farbcodes
und ohne Bild aus.

## Einrichten

```
powershell -ExecutionPolicy Bypass -File scripts\Install-Font.ps1     # einmalig: Schrift IBM Plex Mono
powershell -ExecutionPolicy Bypass -File scripts\Install-Style.ps1    # anwenden, nach jeder Änderung wiederholen
```

Danach einen neuen Tab in Windows Terminal öffnen. Laufende Claude-Code-Sitzungen
übernehmen das Thema beim nächsten Start.

`Install-Font.ps1` lädt die Schrift des aktiven Stils (beide nutzen IBM Plex Mono, SIL Open
Font License) und installiert sie nur für den angemeldeten Benutzer, ohne
Administratorrechte.

`Install-Style.ps1` ändert:

| Ort | Was |
|---|---|
| `settings.json` von Windows Terminal | Farbschema und Fensterthema mit dem Namen des Stils; unter `profiles.defaults` Schrift, Abstand, Cursor; ein Profil mit dem Namen des Stils als Standardprofil (feste GUID aus `config\style.json`, ein Wechsel ersetzt es). Die vorhandenen Profile bleiben erhalten. |
| `%USERPROFILE%\.claude\themes\` | zwei Themen je Stil: `ausbruch-frei.json`, `ausbruch-wolke.json` (oder `nachtschicht-glut.json`, `nachtschicht-fernlicht.json`) |
| `%USERPROFILE%\.claude\settings.json` | `theme` (Cloud-Stimmung), `statusLine`, `spinnerVerbs` |
| `%LOCALAPPDATA%\<Stil>\<Stimmung>.png` | das Tab-Symbol, vom Skript gezeichnet |

Vor der ersten Änderung wird jede Einstellungsdatei einmal nach `<Name>.vor-nachtschicht`
kopiert (`backupSuffix` in `config\style.json`; der Name blieb, weil die vorhandenen
Sicherungen so heißen). Schalter:

- `-PreviewDir <Ordner>` schreibt die Ergebnisse in einen Ordner, statt etwas zu ändern.
- `-Remove` nimmt genau die Einträge aller Stile wieder heraus; alles andere in den Dateien
  bleibt, wie es ist. Die Schrift bleibt installiert.

Das Profil startet PowerShell mit `-ExecutionPolicy RemoteSigned` nur für diesen Prozess.
Die Ausführungsrichtlinie des Systems wird nicht verändert, und es wird kein
PowerShell-Profil unter `Dokumente` angelegt.

## Anpassen

`config\style.json`:

| Schlüssel | Inhalt |
|---|---|
| `active` | der Stil, Name einer Datei in `config\styles\` |
| `profileGuid`, `modeVariable`, `backupSuffix` | gemeinsam für alle Stile: Profil in Windows Terminal, Variable `CLAUDE_LOCAL_LOOK`, an der die Statuszeile eine lokale Sitzung erkennt, Endung der Sicherungen |

Eine Stil-Datei in `config\styles\`, danach `scripts\Install-Style.ps1`:

| Abschnitt | Inhalt |
|---|---|
| `modes` | je Stimmung: Hintergrund, Schrift, Cursor, Akzent, blasse Töne, Zeichen, Name; dazu wahlweise `labelInk` und `gaugeInk` = `"rainbow"` (Name und Messlinien im Farbkreis) |
| `rainbow.colors` | der Farbkreis (nur bunte Stile) |
| `ink` | Bedeutungsfarben: in Ordnung, Warnung, Fehler, Glut, Git-Zweig |
| `palette` | die 16 ANSI-Farben des Terminals |
| `glyphs` | Zeichen; `prompt` darf eine Liste sein (dann jedes Mal ein anderes), `gaugeSpray` = Zeichen für gesprühte Messlinien |
| `texts` | deutsche Texte von Eingabezeile, Begrüßung, Statuszeile, `tagline` unter dem Bild |
| `art` | Bild aus Zeichen: `text` (Shell), `bannerText` (`claude-local`), `scale`, Zeichenvorräte `fill`, `spray`, `flightMid`, `flightFar`, Dichte `sprayChance`, `flightDensity`, `flightReach`, `gradientSpan` und die Blockschrift `font` (A–Z, 0–9, `! ? - .`, je 5 Zeilen) |
| `font` | Schrift, Größe, Zeilenhöhe, Quelle für `Install-Font.ps1` |
| `terminal` | Abstand, Cursorform, Farbe der Tab-Leiste und des Fensterrahmens |
| `shell` | `mode` (Stimmung der Shell), Begrüßung an/aus (`greeting`), `rainbow` (bunter Ordnername, wechselnde Farbe des Eingabezeichens), ab wann die Dauer erscheint, Farben der Eingabe |
| `claude` | Themen für Claude Code (`themes`), Stimmungen für lokal und Cloud, Wartetexte (`spinnerVerbs`), Schwellen der Statuszeile |

Beispiele: Ein anderes Wort im Bild ist `"text": "FREIHEIT"`. Ein festes Eingabezeichen
ist `"prompt": "»"`. Ein neuer Stil ist eine Kopie einer Stil-Datei mit anderem `name`
und `claude.themePrefix`.

Änderungen an Eingabezeile, Begrüßung, Bild und Statuszeile wirken sofort im nächsten Tab
oder beim nächsten Aufruf, weil die Skripte die Stil-Datei bei jedem Start lesen. Nur für
Windows Terminal und die Dateien von Claude Code muss `Install-Style.ps1` erneut laufen.

Die Schlüssel unter `claude.themes.*.overrides` sind die Farbnamen von Claude Code
(`claude`, `text`, `permission`, `diffAdded` ...). Unbekannte Namen ignoriert Claude Code
stillschweigend.

## Aufbau

```
config\style.json            welcher Stil gilt, was alle Stile teilen
config\styles\*.json         je Stil: Farben, Zeichen, Texte, Blockschrift
scripts\lib\Style.ps1        Bausteine: Stil lesen, Farben, Farbkreis, Messlinien, Tönen des Terminals, Messwerte
scripts\lib\CharArt.ps1      Bilder aus Zeichen: Blockschrift, Füllung, Sprühnebel, ausbrechende Zeichen
scripts\style\Shell.ps1      richtet die interaktive Shell ein (Eingabezeile, Begrüßung, Funktion claude)
scripts\style\Statusline.ps1 Statuszeile von Claude Code
scripts\Install-Style.ps1    wendet den aktiven Stil auf Windows Terminal und Claude Code an
scripts\Install-Font.ps1     installiert die Schrift
```

`lib\Style.ps1` liest die Stil-Dateien selbst und nicht über `lib\Config.ps1`: Shell und
Statuszeile laden nur diese Datei (und `CharArt.ps1`), damit sie schnell starten und
`$ErrorActionPreference = 'Stop'` aus `_common.ps1` nicht in die interaktive Shell gerät.

So kommt die Stimmung zustande:

- **Tönen des Fensters:** `Set-TerminalPalette` schickt die Steuerfolgen OSC 10, 11 und 12
  (Schrift, Hintergrund, Cursor). Das geschieht nur in Windows Terminal, nur wenn der Stil
  installiert ist und nur, wenn die Ausgabe nicht umgeleitet ist.
- **`claude` in der Shell** ist eine Funktion, die das Fenster auf die Cloud-Stimmung
  stellt, `claude.exe` mit allen Argumenten startet und danach zurückkehrt.
- **`claude-local`** setzt `CLAUDE_LOCAL_LOOK` auf die lokale Stimmung, stellt das Fenster
  um und übergibt für diesen Start das lokale Thema und die Statuszeile mit 5-Sekunden-Takt
  (`Get-LocalLookSettings`). Die Statuszeile erkennt an der Variable, ob sie Grafikkarten
  oder das Limit zeigt.
- **Das Bild** setzt `Get-CharArt` (`lib\CharArt.ps1`): Wort → Raster aus Blöcken der
  Blockschrift, so breit gezogen (`scale`), wie das Fenster erlaubt, dann Zelle für Zelle
  Füllung, Sprühnebel oder ausbrechende Zeichen mit Farbe aus dem Farbkreis. Mit festem
  Startwert (`-Seed`) entsteht immer dasselbe Bild; das nutzt `Test-Setup.ps1`.

## Gemessen und nicht gemessen

Gemessen am 2026-11-17 (Windows PowerShell 5.1), „Ausbruch“:

| | Dauer |
|---|---|
| Bild UNZENSIERT, erstes Zeichnen im Prozess (Begrüßung) | etwa 145 ms |
| dasselbe Bild, weitere Male | etwa 50 ms |
| Bild FREI vor `claude-local` | etwa 23 ms |
| `lib\Style.ps1` laden | etwa 60 ms |
| ein Lauf der Statuszeile (lokal, mit `nvidia-smi`) | etwa 480 ms |

Für „Nachtschicht“ gemessen am 2026-11-14: Start der Shell mit Begrüßung etwa 440 ms, eine
Eingabezeile im Git-Ordner etwa 30 ms, ein Lauf der Statuszeile etwa 380 ms.

Geprüft: `Test-Setup.ps1` (Stil-Dateien vollständig, Blockschrift stimmig, Bild passt in
die Breite und fällt in zu schmalen Fenstern weg, Messlinien genau so breit wie verlangt,
Statuszeile liest Modell und Kontext von stdin). Begrüßung, Eingabezeile, Banner und beide
Statuszeilen wurden als Bild gerendert und angesehen (eigener Renderer, Schrift Cascadia
Mono); „Nachtschicht“ sieht mit dem umgebauten Code aus wie vorher. `Install-Style.ps1`
ersetzt beim Wechsel Schema, Thema, Profil und Themen-Dateien, ein zweiter Lauf ändert
nichts mehr.

**Nicht geprüft:** das Aussehen im echten Windows-Terminal-Fenster mit IBM Plex Mono,
insbesondere ob `✦`, `✧` und `◇` dort genau eine Spalte breit sind, und ob Claude Code die
Themen „Ausbruch · Frei“ und „Ausbruch · Wolke“ ohne Meldung annimmt.

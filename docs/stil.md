# Erscheinungsbild

Ein gemeinsames Aussehen für die Kommandozeile, für den eigenen Agenten Unzensiert, für
Claude Code und für `claude-local`. Es gibt zwei Stile; welcher gilt, steht in
`config\style.json`:

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
  durch den Farbkreis gefärbt. Die Einzelheiten machen es zu Graffiti:
  - **Licht von oben:** die obere Zeile jedes Buchstabens ist aufgehellt, die untere
    abgedunkelt (`light`).
  - **Schatten:** rechts unten hinter den Buchstaben ein dunkler Schatten aus `:;.`, als
    stünden sie vor der Wand.
  - **Farbnasen:** von Unterkanten läuft Farbe herunter, `|!:` mit einem Tropfen `'.°`
    am Ende.
  - **Sprühnebel** aus leichten Zeichen (`.,:;'~*+^`) um die Buchstaben, der letzte
    Buchstabe bröckelt.
  - **Ausbruch:** rechts brechen Zeichen aus und fliegen davon, erst dichte, dann
    `+*=~^%<>/\`, am Ende nur noch Punkte und Striche, immer blasser.
  - **Funken** `✦ ✧ * +` hier und da im freien Raum.

  Jedes Bild ist anders; auch die Farben beginnen jedes Mal an einer anderen Stelle des
  Kreises.
- **Die Wand.** Hinter dem Terminal liegt ein Bild aus Zeichen: rechts unten FREI, darum
  gesprühte Zeichen, dicht in der Ecke und zur Mitte hin immer dünner, mit 20 %
  Deckkraft, damit die Schrift davor lesbar bleibt. `Install-Style.ps1` zeichnet sie bei
  jedem Lauf neu.
- **Überall Zeichen, die davonfliegen:** am Ende jeder Eingabezeile und jeder
  Statuszeile, vor dem Spruch der Begrüßung und nach dem Abschied von `claude-local`. Die
  Trennzeichen zwischen den Teilen einer Zeile sind gesprüht (`· * + ~ : %` in einer
  zufälligen Farbe). In der Wolke bleibt es schlicht.
- **Sprühlinie** unter jedem Bild: ein Strich aus `~=-_.,:'^`, an den Enden dünn, in der
  Mitte dicht und hell.
- **Ein Spruch** bei jeder neuen Shell, etwa „Kein Filter. Keine Leine.“, „Deine Karten,
  deine Regeln.“ oder „Ausbrechen ist auch eine Richtung.“
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

**Shell** (Profil „Ausbruch“ in Windows Terminal), hier ohne Farben und in der ersten
Fassung ohne Schatten, Farbnasen, Sprühlinie und Spruch (das Bild ist jetzt 10 Zeilen hoch):

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

Darunter folgen in der aktuellen Fassung die Sprühlinie, nach der Zeile mit dem Server
der Spruch in Regenbogenfarben, und jede Eingabezeile endet mit ein paar davonfliegenden
Zeichen.

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

**`claude`** (Cloud) beginnt eine interaktive Sitzung mit dem Bild **WOLKE**, ganz in
Cyan: dieselbe Technik, aber nur eine Farbe. Mit `-p`/`--print` oder Eingabe über eine
Pipe erscheint es nicht.

**Nach einer `claude-local`-Sitzung** verabschiedet sich der Stil mit einer Sprühlinie und
„✦ Sitzung vorbei nach 23 min. Die Zeichen fliegen weiter.“

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

## Die Oberfläche von Unzensiert

Unzensiert zeichnet sein Terminal selbst (`scripts\lib\AgentUi*.ps1`), anders als Claude
Code, bei dem nur Farbthema, Wartetexte und Statuszeile einstellbar sind. Jedes Element
nimmt Farben und Zeichen aus dem aktiven Stil (Abschnitt `agent` der Stil-Datei, Farben der
Stimmung „Frei“ bzw. „Glut“) und seine Texte aus `config\unzensiert-texte.json`. So sieht
eine Sitzung in „Ausbruch“ aus, hier ohne Farben (erzeugt mit
`scripts\Show-AgentDesign.ps1 -Width 118`, gekürzt):

```
      :   `               ` ;   :        : ~         :        ✦ Unzensiert 1.0.0    Mittwoch, 18. November  ·  07:37
  BIXK8%RXRI  0W%TBX&Z ' ;0SUR&MU0N#  $U$#UX  I /
  $S.;..:::.;;SE;;;:..WK^ SS';.:::;..:. MU;.;: +              Modell    local-coder  Qwen 3.6 27B, unzensiert, z…
  0Z0WUIUU    XS8MRE0Z  ;:U0TSEBEN      M@;; S >    ,         Kontext   131.072 Tokens · fasst bei 80 % zusammen
  @@.:.;;::.  &N;;::B8::  %%;;.;;.:;  ' <&:.E$                Projekt   design  design-ui ±15
  Z@;:        E8;:  : 8%  @SE08WMSR#  @RRTTR~0    \           Karten    5070 Ti  $#=X@X+#WM#·  14,3 / 15,9 GB
    ;.          .;  |   ::  ...::;:::.  ;.....                          3060     $=%=#&$+#*··  10,0 / 12,0 GB
                    .                                         Rechte    ask  fragt vor Befehlen und Änderungen
                                                              Regeln    CLAUDE.md
                                               % %  :         Server    http://127.0.0.1:8080  ·  läuft

   -         `    ' , - ~ `~' '~ :~-. ~ ,-.^-_._ -:- -~: ^`==,`,^'.=__~~'~,'-~=:,. _=:,,  = =  `  ~ ~ =  ~
  ~   „Denk selbst. Bau selbst.“
  Enter senden · Shift+Enter neue Zeile · Esc anhalten · Shift+Tab Rechte · /help alles

 ✦ Unzensiert  local-coder  %  Kontext $M······ 23 %  +  Rechte ask  %  design design-ui ±15                    07:37
» Baue in calc.py eine Funktion mul(a, b), schreib einen Test dafür und lass alle Tests laufen.

  ∴ 6,4 s gedacht · 365 Tokens
✦ Plan
   --_: '' _~
  Ich schaue mir zuerst calc.py an, baue dann mul ein und prüfe alles mit pytest. Die Funktion soll auch mit
  Kommazahlen funktionieren, deshalb bekommt sie einen eigenen Test, der genau das prüft – so fällt ein Fehler sofort
  auf.
  • Bestand lesen
    ◦ vorhandene Tests ansehen
  1. Test schreiben
  ✓ Projektregeln gelesen
  ○ README ergänzen

  ╭─ python ──────────────────────────────────────────────────────
  │ def mul(a, b):
  │     return a * b  # auch für float
  ╰───────────────────────────────────────────────────────────────

✎ Edit  calc.py
  ⎿  ✓ Zeile 5  ·  -2 +2
     5   def mul(a, b):
     6 -     """Multipliziert."""
     7 -     return a + b
     6 +     """Multipliziert zwei Zahlen."""
     7 +     return a * b

❯ Bash  python -m pytest -q
  ⎿  ✗ Ende 1  ·  1,8 s
     ..F
     … +4 Zeilen
     FAILED tests/test_calc.py::test_mul_float - assert 2 == 2.0
     1 failed, 2 passed in 0.08s

  ╭─ ! Der Wächter fragt  ❯ PowerShell ───────────────────────────────────────────────────────────────────────────
  │ Remove-Item -Recurse -Force build
  │ Grund: guard rule delete-recursive: Rekursives Loeschen fragt immer nach
  ╰───────────────────────────────────────────────────────────────────────────────────────────────────────────────
   j  ja     n  nein   ›

✦ Fertig: mul multipliziert jetzt, und der neue Test prüft auch Kommazahlen.

   Datei              │ Änderung
  ────────────────────┼───────────────────────
   calc.py            │ mul gibt a * b zurück
   tests/test_calc.py │ neu, 3 Tests

  ✦ Übermalt in 1 min 24 s  ·  9 Runden  ·  3 Dateien geändert  ·  1.873 Tokens  ·  61 tok/s  +\:`
```

Die Elemente, von oben nach unten:

| Element | Was es zeigt | „Ausbruch“ | „Nachtschicht“ |
|---|---|---|---|
| **Begrüßung** | Bild aus Zeichen (`agent.bannerText`) und daneben die Angaben der Sitzung: Version, Datum, Modell mit Beschreibung, Kontextfenster, Projekt mit Git-Stand, Speicher jeder Grafikkarte, Rechte, Projektanweisungen, Server; in schmalen Fenstern (unter `bannerWidth` + 52 Spalten) darunter. Dann Sprühlinie, Spruch und Tasten | Bild FREI, Spruch in den Farben des Kreises | statt des Bilds der gesperrte Name `U N Z E N S I E R T` in Glutorange, schlichte Linie |
| **Statuszeile** vor jeder Eingabe | Stimmung und Modell, Kontext als Messlinie mit Prozent, Tempo der letzten Antwort, Rechte (ask ruhig, edits grün, all gelb), Grafikkarten, Ordner und Git, rechts die Uhrzeit. Was nicht ins Fenster passt, fällt weg, das Unwichtigste zuerst (Karten, Tempo, Ordner) | gesprühte Messlinien und Trennzeichen | durchgezogene Messlinien |
| **Eingabe** | Eingabezeichen in wechselnder Farbe; nach Enter steht die eigene Nachricht auf einem farbigen Balken über die ganze Breite | Zeichen und Farbe wechseln bei jeder Eingabe | `»` in Messing |
| **Wartezeile** | solange nichts anderes läuft: drehendes Zeichen, was gerade geschieht (ein Wartetext des Stils, „denkt · 340 Tokens“, „schreibt Write“, „läuft“, „Abschlussprüfung“, „fasst die Unterhaltung zusammen“), die Zeit bis jetzt, „Esc hält an“. Sie verschwindet, sobald etwas anderes erscheint | funkelnder Stern, der Wartetext läuft durch den Farbkreis, davonfliegende Zeichen | `◐◓◑◒` in Glutorange, ein Licht läuft durch das Wort |
| **Tab und Taskleiste** | Titel des Fensters: was Unzensiert tut und in welchem Ordner; in Windows Terminal dazu der Fortschrittskreis am Tab (OSC 9;4), rot nach einem Fehler bis zur nächsten Eingabe. Beim Beenden kommt der alte Titel zurück | | |
| **Denken** | danach eine leise Zeile „∴ 6,4 s gedacht · 365 Tokens“; mit `/think` das Denken selbst, blass und kursiv hinter `┊` | | |
| **Antwort** | Zeichen des Stils vor der ersten Zeile; Markdown: Überschriften (die erste im Farbkreis mit gesprühtem Strich), Listen mit einem Zeichen je Ebene, Zahlen, offene und erledigte Aufgaben (`○`, `✓`), Zitate (`▌`), Trennlinien, Tabellen mit ausgerichteten Spalten, `Code` auf getöntem Grund, **fett**, *kursiv*, ~~durchgestrichen~~, Links (in Windows Terminal anklickbar). Jede Zeile wird an Wortgrenzen umbrochen, Listen hängend eingerückt | Aufzählungszeichen und Überschriften im Farbkreis | in Glutorange |
| **Code** | im Rahmen mit Namen der Sprache, in den Farben der Eingabezeile der Shell (`shell.syntax`): Schlüsselwörter, Zeichenketten, Zahlen, Kommentare, Variablen, Funktionen, Typen. Python, PowerShell, Bash, JavaScript/TypeScript, C-artige (C, C++, C#, Java, Go, Rust, Arduino …), JSON, YAML, INI/TOML, SQL, Lua, Batch, HTML/XML, CSS, Diff | | |
| **Werkzeuge** | Kopfzeile mit Zeichen und Farbe des Werkzeugs (`agent.tools`), Befehle in den Farben ihrer Shell; darunter `⎿` mit Haken oder Kreuz und Dauer. Befehle: Anfang und Ende der Ausgabe (dazwischen „… +4 Zeilen“), Fehlerzeilen rot, Erfolg grün. Read: Zeilen; Write: neu oder ersetzt, die ersten Zeilen mit Nummern; Glob und Grep: Treffer mit Datei und Zeile | ❯ Orange, ≡ Cyan, ✎ Pink, ✚ Limette, ⌕ Violett und Gelb | gedämpfte Werkstattfarben |
| **Änderungen** (Edit) | Diff mit Zeilennummern: unveränderte Zeilen blass, entfernte und hinzugefügte auf rot und grün getöntem Grund über die ganze Breite, die geänderten Zeichen kräftiger, der Code in seinen Farben; lange unveränderte Strecken zusammengefaltet (`⋯`) | | |
| **Rückfrage** | ein Rahmen: der Befehl in seinen Farben, bei Edit der Diff, bei Write der Anfang der Datei, darunter der Grund; dann die Tasten als Schilder `j` ja, `i` immer (mit der Regel, etwa `Bash(python:*)`), `n` nein. Danach ersetzt die Antwort die Tasten | Gelb; fragt der Wächter, Pink mit `!` und ohne „immer“ | Messing, beim Wächter Glutorange |
| **Hinweise** | Zeichen je Art: `·` blass, `✓` in Ordnung, `!` Warnung, `✗` Fehler, lange Hinweise umbrochen | | |
| **Ende einer Anfrage** | „✦ Übermalt in 1 min 24 s · 9 Runden · 3 Dateien geändert · 1.873 Tokens · 61 tok/s“ mit einem Wort des Stils (`agent.doneVerbs`); nach Esc „■ angehalten nach 12 s“, nach einem Abbruch rot | Gesprüht, Ausgebrochen, Getaggt … | Geschmiedet, Gefeilt, Gehärtet … |
| **Übersichten** | `/help` (Tasten, Befehle, Abläufe), `/status` (Kontext mit Messlinie, Tokens der Sitzung, Rechte, Erlaubtes, Regeln, geänderte Dateien), `/model` und `/resume` als Listen unter kleinen Überschriften | | |
| **Abschied** | Sprühlinie, „Sitzung vorbei nach 23 min. Die Zeichen fliegen weiter.“, Anfragen, Runden, gelesene (davon aus dem Cache) und geschriebene Tokens, geänderte Dateien, was mit den Modellen geschah | | „Sitzung vorbei nach 23 min.“ |

Alle Elemente auf einmal, ohne Modell und ohne Server:

```
powershell -ExecutionPolicy Bypass -File scripts\Show-AgentDesign.ps1                    # im aktiven Stil
powershell -ExecutionPolicy Bypass -File scripts\Show-AgentDesign.ps1 -Style nachtschicht # anderer Stil, ohne Wechsel
```

Die Beispielsitzung steht in `tests\agent-design.json`; `-Width` stellt eine Fensterbreite
nach, `-OutFile` schreibt die Ausgabe mit Steuerzeichen in eine Datei.

Ist die Ausgabe umgeleitet (`unzensiert -p`, Benchmark), zeichnet Unzensiert nichts davon;
die Standardausgabe enthält nur das Ergebnis.

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
| `%LOCALAPPDATA%\<Stil>\wand.png` | nur bei Stilen mit `terminal.wall`: die Wand aus Zeichen, als `backgroundImage` des Profils (rechts unten, nicht gestreckt, Deckkraft aus `opacity`) |

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
| `modes` | je Stimmung: Hintergrund, Schrift, Cursor, Akzent, blasse Töne, Zeichen, Name; dazu wahlweise `labelInk` und `gaugeInk` = `"rainbow"` (Name und Messlinien im Farbkreis) und `trail` (gesprühte Trennzeichen, davonfliegende Zeichen) |
| `rainbow.colors` | der Farbkreis (nur bunte Stile) |
| `ink` | Bedeutungsfarben: in Ordnung, Warnung, Fehler, Glut, Git-Zweig |
| `palette` | die 16 ANSI-Farben des Terminals |
| `glyphs` | Zeichen; `prompt` darf eine Liste sein (dann jedes Mal ein anderes), `gaugeSpray` = Zeichen für gesprühte Messlinien, `sepSpray` = gesprühte Trennzeichen |
| `texts` | deutsche Texte von Eingabezeile, Begrüßung, Statuszeile, `tagline` unter dem Bild, `sprueche` (Liste, jedes Mal einer), `farewell` (Abschied nach `claude-local`) |
| `art` | Bild aus Zeichen: `text` (Shell), `bannerText` (`claude-local`), `cloudText` (`claude`, einfarbig), `scale`, Zeichenvorräte `fill`, `spray`, `flightMid`, `flightFar`, Dichte `sprayChance`, `flightDensity`, `flightReach`, `gradientSpan`; Einzelheiten `light`, `shadow`, `dripBody`, `dripEnd`, `dripChance`, `dripLength`, `sparkle`, `sparkleChance`, `line` (Sprühlinie); die Blockschrift `font` (A–Z, 0–9, `! ? - .`, je 5 Zeilen) |
| `font` | Schrift, Größe, Zeilenhöhe, Quelle für `Install-Font.ps1` |
| `terminal` | Abstand, Cursorform, Farbe der Tab-Leiste und des Fensterrahmens; `wall` = Wand aus Zeichen hinter dem Terminal (`text`, Größe in `cols` × `rows`, `fontPixels`, `opacity`, `alignment`) |
| `shell` | `mode` (Stimmung der Shell), Begrüßung an/aus (`greeting`), `rainbow` (bunter Ordnername, wechselnde Farbe des Eingabezeichens), `trail` (Spalten davonfliegender Zeichen am Ende der Eingabezeile), ab wann die Dauer erscheint, Farben der Eingabe |
| `claude` | Themen für Claude Code (`themes`), Stimmungen für lokal und Cloud, Wartetexte (`spinnerVerbs`, auch für die Wartezeile von Unzensiert), Schwellen der Statuszeile |
| `agent` | die Oberfläche von Unzensiert (siehe unten) |

Der Abschnitt `agent` (fehlt er, gelten schlichte Vorgaben):

| Schlüssel | Inhalt |
|---|---|
| `bannerText`, `bannerScale`, `bannerWidth` | Bild der Begrüßung (Wort, größte Verbreiterung, Spalten für das Bild neben den Angaben) |
| `title` | Name über den Angaben in Stilen ohne `art` |
| `spinner`, `spinnerInk` | Zeichen der Wartezeile (eins je Bild) und ihre Farbe |
| `verbInk`, `headingInk`, `promptInk` | Farbe des Wartetexts, der Überschriften und Abschlusszeilen, des Eingabezeichens |
| `verbs` | Wartetexte; ohne den Schlüssel die von `claude.spinnerVerbs` |
| `doneVerbs` | Wörter für eine fertige Anfrage („Gesprüht in 42 s“) |
| `marks` | Zeichen für Antwort, Denken, Ergebnis (`corner`), Ende, Angehalten, Mitlesen des Denkens |
| `notes` | Zeichen der Hinweise: `dim`, `ok`, `warn`, `error` |
| `bullets`, `quote`, `box` | Aufzählungszeichen je Ebene, Zeichen vor Zitaten, Rahmen (oben links, unten links, Linie, Seite) |
| `rule` | Trennlinien: `spray` (gesprüht) oder `line` |
| `trail` | Spalten davonfliegender Zeichen am Ende von Warte- und Abschlusszeile (0 = keine) |
| `tools` | je Werkzeug `icon` und `ink` |
| `diffTint`, `diffStrong` | wie stark der Grund entfernter und hinzugefügter Zeilen und der geänderten Zeichen getönt ist (1 = gar nicht) |

Farben sind `#RRGGBB`, `rainbow` (Farbkreis), `shimmer` (ein Licht läuft durch) oder
`accent` (Akzent der Stimmung). Die Texte der Oberfläche, die in jedem Stil gleich sind
(Beschriftungen, Hinweise, Rückfragen, Hilfe), stehen in `config\unzensiert-texte.json`;
`{0}`, `{1}` sind Platzhalter, eine Liste mit zwei Einträgen unter `count` ist Einzahl und
Mehrzahl. `Test-Setup.ps1` prüft, dass jeder Text, nach dem der Code fragt, dort steht.

Beispiele: Ein anderes Wort im Bild ist `"text": "FREIHEIT"`. Ohne Farbnasen:
`"dripChance": 0`. Ohne Wand: den Abschnitt `terminal.wall` löschen und
`Install-Style.ps1` laufen lassen. Mehr oder weniger Wand: `opacity` zwischen 0,1 und 0,3. Ein festes Eingabezeichen
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
scripts\lib\CharArt.ps1      Bilder aus Zeichen: Blockschrift, Füllung, Licht, Schatten, Farbnasen, Sprühnebel, Funken, ausbrechende Zeichen; die Wand als PNG
scripts\lib\AgentUi.ps1      Oberfläche von Unzensiert: Begrüßung, Wartezeile, Hinweise, Eingabe, Statuszeile, Übersichten, Abschied
scripts\lib\AgentUiMarkdown.ps1  die Antwort: Markdown, Umbruch, Tabellen, Farben von Code
scripts\lib\AgentUiTools.ps1     Werkzeuge, Diffs, Rückfragen
config\unzensiert-texte.json  Texte der Oberfläche von Unzensiert
scripts\Show-AgentDesign.ps1  zeigt jedes Element der Oberfläche mit tests\agent-design.json
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
- **Das Bild** setzt `Get-CharArtCells` (`lib\CharArt.ps1`): Wort → Raster aus Blöcken
  der Blockschrift, so breit gezogen (`scale`), wie das Fenster erlaubt, dann Zelle für
  Zelle Buchstabe, Farbnase, Schatten, Sprühnebel, ausbrechendes Zeichen oder Funke, die
  Farbe aus dem Farbkreis (oder einer Farbe), aufgehellt oder zum Hintergrund hin
  verblasst. `Format-ArtCells` macht daraus Terminalzeilen, `Save-ArtCellsImage` ein PNG
  (die Wand aus `New-CharWall`). Mit festem Startwert (`-Seed`) entsteht immer dasselbe
  Bild; das nutzt `Test-Setup.ps1`.

## Gemessen und nicht gemessen

Gemessen am 2026-11-17 (Windows PowerShell 5.1), „Ausbruch“ mit Schatten, Farbnasen und
Funken:

| | Dauer |
|---|---|
| Bild UNZENSIERT, erstes Zeichnen im Prozess (Begrüßung) | etwa 240 ms (vorher ohne Einzelheiten 145 ms) |
| dasselbe Bild, weitere Male | etwa 75 ms |
| Bild FREI vor `claude-local` | etwa 35 ms |
| Wand zeichnen und als PNG speichern (`Install-Style.ps1`) | etwa 310 ms |
| `lib\Style.ps1` laden | etwa 70 ms |
| ein Lauf der Statuszeile (lokal, mit `nvidia-smi`) | etwa 480 ms |

Oberfläche von Unzensiert, gemessen am 2026-11-18 (Windows PowerShell 5.1, Fenster 120
Spalten, Mittel aus mehreren Durchläufen nach einem ersten; nebenher lief ein Benchmark):

| | Dauer |
|---|---|
| alle Skripte laden (`_common.ps1`) | etwa 265 ms (vorher 235 ms) |
| Begrüßung, erstes Mal im Prozess (mit `nvidia-smi`, Git, Bild) | etwa 480 ms |
| Statuszeile (mit `nvidia-smi`) | etwa 90 ms |
| ein Bild der Wartezeile (höchstens zehn je Sekunde) | etwa 4 ms |
| eine Zeile der Antwort mit Markdown, im Mittel | etwa 2 ms |
| Absatz von 220 Zeichen mit fett, Code und Link | etwa 4 ms |
| Zeile Code mit Farben | etwa 1 ms |
| Diff des Beispiels (3 Zeilen) / 60 Zeilen mit 8 Änderungen | etwa 11 ms / 34 ms |

Für „Nachtschicht“ gemessen am 2026-11-14: Start der Shell mit Begrüßung etwa 440 ms, eine
Eingabezeile im Git-Ordner etwa 30 ms, ein Lauf der Statuszeile etwa 380 ms.

Geprüft: `Test-Setup.ps1` (Stil-Dateien vollständig, Blockschrift stimmig, Bild passt in
die Breite und fällt in zu schmalen Fenstern weg, das Wolke-Bild bleibt in seiner Farbe,
Messlinien, Sprühlinie und Zeichenspur genau so breit wie verlangt, die Wand hat die
verlangte Größe, Statuszeile liest Modell und Kontext von stdin). Wolke-Bild, Abschied und
Wand wurden ebenfalls gerendert und angesehen. Begrüßung, Eingabezeile, Banner und beide
Statuszeilen wurden als Bild gerendert und angesehen (eigener Renderer, Schrift Cascadia
Mono); „Nachtschicht“ sieht mit dem umgebauten Code aus wie vorher. `Install-Style.ps1`
ersetzt beim Wechsel Schema, Thema, Profil und Themen-Dateien, ein zweiter Lauf ändert
nichts mehr.

Die Oberfläche von Unzensiert wurde mit `Show-AgentDesign.ps1` in beiden Stilen und in 80,
100 und 120 Spalten gerendert und angesehen (eigener Renderer, IBM Plex Mono). Ein Test lässt
eine Antwort stückweise mit Pausen eintreffen: Wartezeile, rohe Zeilen und umgebrochene
Zeilen hinterlassen nichts, das Endbild gleicht dem einer Antwort am Stück.
`Test-Agent.ps1` prüft Umbruch, Diff, Farben von Code (kein Zeichen geht verloren) und die
Vorschau.

**Nicht geprüft:** das Aussehen im echten Windows-Terminal-Fenster mit IBM Plex Mono,
bei Unzensiert der Titel und der Fortschrittskreis am Tab, der Balken hinter der eigenen
Eingabe nach PSReadLine und die Zeichen `✓ ✗ ✎ ✚ ⌕ ❯ ≡ ⎿` (eine Spalte breit?),
wie stark die Wand bei 20 % Deckkraft im Fenster wirkt,
insbesondere ob `✦`, `✧` und `◇` dort genau eine Spalte breit sind, und ob Claude Code die
Themen „Ausbruch · Frei“ und „Ausbruch · Wolke“ ohne Meldung annimmt.

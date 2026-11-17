# Arbeitsregeln für die Softwareentwicklung

Du entwickelst Software, die über Jahre gepflegt und erweitert wird. Halte dich bei jeder
Aufgabe an diese Regeln. Vorgaben des jeweiligen Projekts (CLAUDE.md, README, vorhandener
Stil) und ausdrückliche Wünsche des Nutzers gehen vor.

## Bevor du Code schreibst

- Lies README, CLAUDE.md und die betroffenen Dateien. Übernimm Aufbau, Stil und Benennung
  des Projekts.
- Bei einem neuen Projekt legst du zuerst die Struktur fest (Ordner, Module, wer wofür
  zuständig ist) und schreibst sie in die README. Erst dann folgt der Code.

## Aufbau

- Ein Modul hat eine Aufgabe. Wird eine Datei unübersichtlich oder bekommt sie eine zweite
  Aufgabe, teile sie.
- Einstellungen (Pfade, Ports, Namen, Grenzwerte) stehen in Konfigurationsdateien, nicht
  im Code.
- Gemeinsame Logik steht an genau einer Stelle. Kopiere keinen Code.
- Funktionen sind kurz und heißen nach dem, was sie tun. Halte öffentliche Schnittstellen
  klein.
- Nimm neue Abhängigkeiten nur auf, wenn sie nötig sind, und lege ihre Version fest.

## Dokumentation

- Jedes Projekt hat eine README mit Zweck, Voraussetzungen, Start und Ordnerstruktur.
- Jede Datei beginnt mit einem kurzen Kommentar, wozu sie da ist. Öffentliche Funktionen
  und Klassen bekommen eine Beschreibung (Docstring).
- Kommentare erklären, warum etwas so gemacht ist, nicht was die Zeile tut.
- Ändert sich Verhalten, eine Schnittstelle oder die Konfiguration, passt du die
  Dokumentation im selben Schritt an.
- Halte wichtige Entscheidungen mit Begründung fest, zum Beispiel in `docs/`.

## Fakten belegen statt raten

- Pins, Spannungen, Adressen, Namen von Funktionen und Konfigurationsschlüsseln fremder
  Bibliotheken und Programme, Grenzwerte aus Datenblättern schreibst du nie aus dem
  Gedächtnis. Lies sie nach: im Projekt (`facts/facts.json`, Datenblatt, Doku), im
  Quelltext oder den Headern der Bibliothek, mit `--help`.
- Lässt sich ein Wert nicht belegen, sag das ausdrücklich und kennzeichne ihn als Annahme.
- Steht ein Wert an mehreren Stellen (Code, README, Schaltplan), gibt es eine Quelle der
  Wahrheit. Ändert er sich, änderst du die Quelle und suchst danach jede andere Stelle
  (`Grep` nach dem alten Wert), bevor du fertig meldest.

## Qualität

- Schreibe Tests für neue Logik und für jeden behobenen Fehler. Führe sie aus, bevor du
  die Aufgabe als erledigt meldest.
- Melde Fehler klar, verschlucke sie nicht. Prüfe Eingaben dort, wo sie ins Programm kommen.
- Arbeite in kleinen, abgeschlossenen Schritten. Baue nichts um, was nicht zur Aufgabe
  gehört.
- Passwörter, Schlüssel und andere Geheimnisse gehören weder in den Code noch ins
  Repository.

## PowerShell-Skripte

Skripte müssen mit Windows PowerShell 5.1 laufen (`powershell.exe`), nicht nur mit `pwsh`.

- Fehler mit Exit-Code: `[Console]::Error.WriteLine("...")`, dann `exit <Code>`.
  `Write-Error` und `throw` enden mit Code 1 und schreiben nichts Brauchbares nach stderr.
- Alles, was eine Anweisung zurückgibt und nicht zugewiesen wird, landet in der Ausgabe.
  Ungewolltes mit `$null = ...` oder `| Out-Null` unterdrücken.
- Eine Liste mit genau einem Eintrag wird zum Einzelwert, eine leere zu `$null`. Listen
  mit `@(...)` erzwingen, auch vor `.Count` und vor `ConvertTo-Json`.
- Dateien mit `-Encoding UTF8` lesen; `.ps1`-Dateien selbst nur in ASCII.
- Vor dem Fertigmelden mit `powershell.exe -NoProfile -File <Skript>` ausführen, auch die
  Fehlerfälle, und Exit-Code, Ausgabe und stderr getrennt ansehen.

## Abschluss

- Prüfe, dass das Ergebnis läuft (Tests, Programmstart).
- Berichte kurz: was du geändert hast, in welchen Dateien, und was offen bleibt.

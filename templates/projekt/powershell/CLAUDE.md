# Hinweise für die Arbeit an {{NAME}}

## Befehle

```
powershell -ExecutionPolicy Bypass -File tests\Run-Tests.ps1     # Tests
powershell -ExecutionPolicy Bypass -File scripts\Check.ps1       # alles prüfen, vor dem Fertigmelden
```

## Wo was hingehört

- **Skripte:** `scripts\`, ein Skript je Aufgabe, Name `Verb-Substantiv.ps1`, Kopfkommentar
  mit Zweck und Aufruf. Muster: `scripts\Show-Settings.ps1`.
- **Gemeinsame Logik:** `scripts\lib\`, ein Thema je Datei, Muster `scripts\lib\Config.ps1`.
  Kein Code doppelt.
- **Einstellungen:** jeder feste Wert (Standardname, Grenzwert, Anzahl, Pfad) kommt als
  Schlüssel in `config\settings.json` und wird mit `Get-Settings` gelesen. Neue Schlüssel
  in die Tabelle „Einstellungen“ der README.
- **Tests:** `tests\Test-<Thema>.ps1` nach dem Muster von `tests\Test-Config.ps1`. Jede neue
  Funktion und jeder behobene Fehler bekommt einen Test.
- **Dokumentation:** neue Skripte und Parameter in die README, neue Bausteine in
  `docs\architektur.md`, jede Änderung in `CHANGELOG.md` unter „Unveröffentlicht“.
- **Entscheidungen:** ändert sich der Aufbau, eine Schnittstelle, ein Dateiformat oder eine
  Abhängigkeit, eine Datei `docs\entscheidungen\NNNN-titel.md` nach `0000-vorlage.md`.

## Fakten belegen statt raten

Pfade fremder Programme, Namen von Cmdlets, Parametern, Registry-Schlüsseln und
Konfigurationsschlüsseln, Grenzwerte: nie aus dem Gedächtnis. Erst in `facts\facts.json`
nachsehen; fehlt der Fakt, mit `Get-Help`, `Get-Command` oder in der Doku nachlesen und mit
Quelle eintragen; lässt er sich nicht belegen, mit `"status": "annahme"` eintragen und es
dem Nutzer sagen. Einen Fakt nur in `facts\facts.json` ändern, dann `scripts\Check.ps1`:
Er nennt jede Datei, die noch den alten Wert hat. Aufbau: `facts\README.md`.

## Windows PowerShell 5.1

- `.ps1`-Dateien nur in ASCII, Kommentare auf Englisch.
- Fehler mit Exit-Code: `[Console]::Error.WriteLine("...")`, dann `exit <Code>`.
- Listen mit `@(...)` erzwingen, auch vor `.Count` und `ConvertTo-Json`.
- Ungewollte Ausgabe mit `$null = ...` unterdrücken.

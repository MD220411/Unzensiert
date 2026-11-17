# Hinweise für die Arbeit an {{NAME}}

## Befehle

```
python -m {{PAKET}}                                          # starten
python -m unittest discover -s tests -t .                   # Tests
powershell -ExecutionPolicy Bypass -File scripts\Check.ps1  # alles prüfen, vor dem Fertigmelden
```

## Wo was hingehört

- **Code:** `{{PAKET}}\`, ein Modul je Aufgabe. Neues Modul nach dem Muster von
  `{{PAKET}}\config.py`: Kopfkommentar, kleine öffentliche Funktionen mit Beschreibung.
- **Einstellungen:** jeder feste Wert (Standardname, Grenzwert, Anzahl, Pfad) kommt als
  Schlüssel in `config\settings.json` und wird über `{{PAKET}}.config.load_settings()`
  gelesen. Neue Schlüssel in die Tabelle „Einstellungen“ der README.
- **Tests:** `tests\test_<modul>.py` nach dem Muster von `tests\test_config.py`. Jede neue
  Funktion und jeder behobene Fehler bekommt einen Test.
- **Dokumentation:** neue Befehle und Optionen in die README, neue Module in
  `docs\architektur.md`, jede Änderung in `CHANGELOG.md` unter „Unveröffentlicht“.
- **Entscheidungen:** ändert sich der Aufbau, eine öffentliche Schnittstelle, ein
  Dateiformat oder eine Abhängigkeit, eine Datei `docs\entscheidungen\NNNN-titel.md` nach
  `0000-vorlage.md` und eine Zeile in der Tabelle dort.
- **Abhängigkeiten:** nur wenn nötig, mit fester Version in `requirements.txt`.

## Fakten belegen statt raten

Pins, Spannungen, Adressen, Namen fremder Funktionen und Konfigurationsschlüssel, Grenzwerte
aus Datenblättern: nie aus dem Gedächtnis. Erst in `facts\facts.json` nachsehen; fehlt der
Fakt, in Datenblatt, Doku oder Quelltext nachlesen und mit Quelle eintragen; lässt er sich
nicht belegen, mit `"status": "annahme"` eintragen und es dem Nutzer sagen. Einen Fakt nur
in `facts\facts.json` ändern, dann `scripts\Check.ps1`: Er nennt jede Datei, die noch den
alten Wert hat. Aufbau: `facts\README.md`.

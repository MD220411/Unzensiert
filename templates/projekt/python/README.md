# {{NAME}}

{{ZWECK}}

## Voraussetzungen

Python 3.10 oder neuer. Weitere Pakete: keine (`requirements.txt`).

## Start

```
python -m {{PAKET}}
```

## Prüfen

```
powershell -ExecutionPolicy Bypass -File scripts\Check.ps1
```

Führt alle Schritte aus `config\check.json` aus (Syntax, Tests, Linter, falls installiert).
Derselbe Befehl läuft vor jedem Commit.

## Aufbau

```
{{PAKET}}\        der Code, ein Modul je Aufgabe
config\           Einstellungen: settings.json (Programm), check.json (Prüfschritte)
tests\            Tests (unittest), eine Datei test_<modul>.py je Modul
scripts\          Check.ps1: der Prüfbefehl
docs\             architektur.md, entscheidungen\
CHANGELOG.md      Änderungen je Version
CLAUDE.md         Hinweise für die Arbeit mit einem Coding-Agenten
```

## Einstellungen

`config\settings.json`, gelesen von `{{PAKET}}\config.py`:

| Schlüssel | Bedeutung |
|---|---|
| `greeting` | Text, den das Programm beim Start ausgibt (Platzhalter der Vorlage) |

## Dokumentation

| Datei | Inhalt |
|---|---|
| [docs/architektur.md](docs/architektur.md) | Module und ihre Aufgaben |
| [docs/entscheidungen/](docs/entscheidungen/README.md) | Entscheidungen mit Begründung |
| [CHANGELOG.md](CHANGELOG.md) | Änderungen je Version |

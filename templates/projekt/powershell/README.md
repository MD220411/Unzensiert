# {{NAME}}

{{ZWECK}}

## Voraussetzungen

Windows PowerShell 5.1 (`powershell.exe`), keine weiteren Module.

## Start

```
powershell -ExecutionPolicy Bypass -File scripts\Show-Settings.ps1
```

## Prüfen

```
powershell -ExecutionPolicy Bypass -File scripts\Check.ps1
```

Führt alle Schritte aus `config\check.json` aus (Syntax und ASCII aller Skripte, Tests).
Derselbe Befehl läuft vor jedem Commit.

## Aufbau

```
scripts\          ein Skript je Aufgabe; Check.ps1 ist der Prüfbefehl
scripts\lib\      gemeinsame Bausteine, ein Thema je Datei
config\           Einstellungen: settings.json (Skripte), check.json (Prüfschritte)
tests\            Tests: Test-<Thema>.ps1, gestartet von Run-Tests.ps1
docs\             architektur.md, entscheidungen\
CHANGELOG.md      Änderungen je Version
CLAUDE.md         Hinweise für die Arbeit mit einem Coding-Agenten
```

## Skripte

| Skript | Zweck |
|---|---|
| `scripts\Show-Settings.ps1` | zeigt die Einstellungen (Platzhalter der Vorlage) |
| `scripts\Check.ps1` | prüft das Projekt |

## Einstellungen

`config\settings.json`, gelesen über `Get-Settings` aus `scripts\lib\Config.ps1`:

| Schlüssel | Bedeutung |
|---|---|
| `greeting` | Text, den `Show-Settings.ps1` ausgibt (Platzhalter der Vorlage) |

## Dokumentation

| Datei | Inhalt |
|---|---|
| [docs/architektur.md](docs/architektur.md) | Skripte, Bausteine und ihre Aufgaben |
| [docs/entscheidungen/](docs/entscheidungen/README.md) | Entscheidungen mit Begründung |
| [CHANGELOG.md](CHANGELOG.md) | Änderungen je Version |

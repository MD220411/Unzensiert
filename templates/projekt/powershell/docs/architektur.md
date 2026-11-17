# Architektur

## Ziel

{{ZWECK}}

## Skripte und Bausteine

| Datei | Aufgabe | Öffentliche Funktionen |
|---|---|---|
| `scripts\lib\Config.ps1` | liest `config\settings.json` | `Get-Settings` |
| `scripts\Show-Settings.ps1` | zeigt die Einstellungen | |
| `scripts\Check.ps1` | Prüfbefehl, Schritte in `config\check.json` | |

## Grundsätze

- Ein Skript, eine Aufgabe. Gemeinsame Logik steht in `scripts\lib\`, nie doppelt.
- Einstellungen stehen in `config\`, nicht in Skripten.
- Skripte sind wiederholbar: Jeder Lauf stellt den Soll-Zustand her.
- Entscheidungen mit Begründung: [entscheidungen/](entscheidungen/README.md).

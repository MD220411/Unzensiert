# Architektur

## Ziel

{{ZWECK}}

## Module

| Modul | Aufgabe | Öffentliche Schnittstelle |
|---|---|---|
| `{{PAKET}}\config.py` | liest `config\settings.json` | `load_settings()` |
| `{{PAKET}}\__main__.py` | Einstieg der Kommandozeile | `main(argv)` |

## Grundsätze

- Ein Modul hat eine Aufgabe. Was andere Module benutzen dürfen, steht in der Tabelle oben;
  alles andere ist intern und beginnt mit einem Unterstrich.
- Einstellungen stehen in `config\`, nicht im Code.
- Entscheidungen mit Begründung: [entscheidungen/](entscheidungen/README.md).

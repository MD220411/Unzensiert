# Hinweise für die Arbeit an diesem Projekt

Lokaler Coding-Agent: Claude Code (`claude-local`) mit llama.cpp (`llama-server`) und
lokalen Modellen, mit Installer für beliebige Windows-Rechner. Entwickelt auf einem Rechner
mit zwei Grafikkarten. Überblick: `README.md`, Aufbau: `docs\architektur.md`.

## Regeln

- **Einstellungen stehen in `config\`**, nie in Skripten. Skripte lesen sie über
  `scripts\lib\Config.ps1`.
- **Projekt und Rechner getrennt.** Die Dateien in `config\` gelten auf jedem Rechner:
  keine festen Laufwerke, Kartennamen oder Kartenaufteilungen. Was nur für einen Rechner
  stimmt (Ordner, `tensor-split`, `device`, Standardmodell), gehört nach
  `config\machine.json`; die steht nicht im Repository (`docs\einrichtung.md`).
- **Das Repository ist öffentlich.** Keine persönlichen Angaben in Dateien, Logs und
  Commit-Nachrichten (Namen, Pfade mit `C:\Users\<name>`, Schlüssel); in der Doku
  `%USERPROFILE%` bzw. `<installRoot>` schreiben.
- **Ein Skript, eine Aufgabe.** Gemeinsame Logik gehört in `scripts\lib\` (ein Thema je
  Datei), eingebunden über `scripts\_common.ps1`.
- **Skripte sind wiederholbar** und haben einen Kopfkommentar mit Zweck und Aufruf.
- **`.ps1`-Dateien nur in ASCII**, Kommentare darin auf Englisch. Windows PowerShell 5.1
  liest Dateien ohne BOM als ANSI.
- **Dokumentation auf Deutsch** in `docs\`. Bei jeder Änderung im selben Schritt anpassen:
  die Beschreibung der Schicht (`backend.md`, `modelle.md`, `agent.md`), die Tabellen der
  `README.md` und ein Eintrag oben in `docs\protokoll.md`.
- **`docs\benchmark.md` ist erzeugt**, nicht von Hand bearbeiten
  (`scripts\Benchmark-Models.ps1 -ReportOnly`).
- **Nach Änderungen an `config\server.json` oder `config\models.json`:**
  `scripts\Restart-Server.ps1`, dann `scripts\Test-Model.ps1`.
- **Nach jeder Änderung an `config\` oder `scripts\`:** `scripts\Test-Setup.ps1`.
  Nach Änderungen an `config\guard.json` oder am Wächter zusätzlich `scripts\Test-Guard.ps1`.
- **Nach Änderungen an `benchmark\`:** `scripts\Test-Tasks.ps1`. Jede neue Aufgabe bekommt
  eine Musterlösung (`solution\`); die Vorlage muss durchfallen, die Lösung bestehen.
- **Nach Änderungen an `templates\` oder `New-Project.ps1`:** `scripts\Test-Templates.ps1`.
- **Nach Änderungen am Installer** (`install.ps1`, `Install.ps1`, `Uninstall.ps1`,
  `Get-Model.ps1`, `Install-LlamaCpp.ps1`, `lib\Config.ps1`, `lib\Machine.ps1`,
  `lib\Download.ps1`, `config\setups.json`, `download` in `config\models.json`):
  `scripts\Test-Install.ps1`. Neue Stufen in `setups.json` mit `Test-Model.ps1` messen und
  in `measured` eintragen.
- **Der Schutz dient dem Rechner des Nutzers** (`docs\sicherheit.md`): keine Regeln zu
  Inhalten, und nichts, was die normale Arbeit des lokalen Modells im Projektordner behindert.
- **Messen statt behaupten.** Aussagen über Tempo oder Qualität brauchen einen Lauf von
  `Test-Model.ps1` oder `Benchmark-Models.ps1`; ungeprüfte Annahmen als solche kennzeichnen.
- **Nichts außerhalb des Repositorys löschen** (Modelle, den Installationsordner, auf dem
  Entwicklungsrechner `E:\LlamaCpp`), ohne dass der Nutzer es ausdrücklich will.

## Prüfen

```
powershell -ExecutionPolicy Bypass -File scripts\Test-Setup.ps1            # Konfiguration und Skripte, ohne Modell, wenige Sekunden
powershell -ExecutionPolicy Bypass -File scripts\Test-Guard.ps1            # Schutzregeln, etwa 25 s
powershell -ExecutionPolicy Bypass -File scripts\Test-Tasks.ps1            # Benchmark-Aufgaben, ohne Modell, etwa 40 s
powershell -ExecutionPolicy Bypass -File scripts\Test-Templates.ps1        # Projektvorlagen, ohne Modell, etwa 20 s
powershell -ExecutionPolicy Bypass -File scripts\Test-Install.ps1          # Installer-Logik, ohne Download und Modell, etwa 30 s
powershell -ExecutionPolicy Bypass -File scripts\Install.ps1 -Plan         # Probelauf des Installers auf diesem Rechner, ändert nichts
powershell -ExecutionPolicy Bypass -File scripts\Test-Model.ps1            # ein Profil, etwa 30 s
powershell -ExecutionPolicy Bypass -File scripts\Benchmark-Models.ps1      # alle Profile, etwa 10 bis 40 min
```

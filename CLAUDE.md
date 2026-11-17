# Hinweise für die Arbeit an diesem Projekt

Lokaler Coding-Agent: der eigene Agent Unzensiert (`unzensiert`, `docs\unzensiert.md`) und
zum Vergleich Claude Code (`claude-local`), beide mit llama.cpp (`llama-server`) und lokalen
Modellen, mit Installer und automatischen Updates für beliebige Windows-Rechner. Entwickelt
auf einem Rechner mit zwei Grafikkarten. Überblick: `README.md`, Aufbau: `docs\architektur.md`.

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
- **Fallen von PowerShell 5.1** (Abschnitt „Aufbau“ in `docs\unzensiert.md`): Variablennamen
  unterscheiden nicht Groß/Klein (`$ui` ist `$script:Ui`, `$agent` ist ein Parameter
  `-Agent`); eine Liste mit einem Element kommt aus einer Funktion als dieses Element
  zurück (`@(...)` beim Aufruf oder `return , $liste`); Werte von `New-Object`,
  `Join-Path`, `Get-Date` sind PSObjects und gehören nicht in JSON für den Server.
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
- **Nach Änderungen am Agenten** (`scripts\unzensiert.ps1`, `scripts\lib\Agent*.ps1`,
  `scripts\lib\Update.ps1`, `config\unzensiert.json`, `config\unzensiert-prompt.md`):
  `scripts\Test-Agent.ps1`; nach Änderungen an Schleife, Werkzeugen oder Rechten auch
  `scripts\Test-Agent.ps1 -WithModel`. Aussagen über Unzensiert gegenüber Claude Code
  brauchen einen Lauf von `Benchmark-Models.ps1` mit beiden Agenten (`-Agent`).
- **Releases nur, wenn der Nutzer es ausdrücklich will**, und nur mit
  `scripts\New-Release.ps1`: ein Release spielt sich bei allen Installationen mit
  automatischen Updates ein. Auf dem Entwicklungsrechner sind die automatischen Updates aus
  (`config\machine.json`, `updates`).
- **Nach Änderungen am Installer** (`install.ps1`, `Install.ps1`, `Uninstall.ps1`,
  `Get-Model.ps1`, `Install-LlamaCpp.ps1`, `lib\Config.ps1`, `lib\Machine.ps1`,
  `lib\Download.ps1`, `config\setups.json`, `download` in `config\models.json`):
  `scripts\Test-Install.ps1`. Neue Stufen in `setups.json` mit `Test-Model.ps1` messen und
  in `measured` eintragen.
- **Nach Änderungen am Planer** (`Plan-Models.ps1`, `lib\Planner.ps1`, `config\planner.json`):
  `scripts\Test-Install.ps1`, dann auf diesem Rechner `scripts\Plan-Models.ps1 -Verify` und
  das Tempo mit dem vorigen Plan vergleichen (`docs\planer.md`). Die Verteilung auf die
  Karten nicht von Hand in `machine.json` tunen, sondern im Planer verbessern.
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
powershell -ExecutionPolicy Bypass -File scripts\Test-Agent.ps1            # Agent Unzensiert, ohne Modell, etwa 5 s (-WithModel: eine Aufgabe, etwa 30 s)
powershell -ExecutionPolicy Bypass -File scripts\Test-Install.ps1          # Installer-Logik, ohne Download und Modell, etwa 30 s
powershell -ExecutionPolicy Bypass -File scripts\Install.ps1 -Plan         # Probelauf des Installers auf diesem Rechner, ändert nichts
powershell -ExecutionPolicy Bypass -File scripts\Plan-Models.ps1 -Verify  # Verteilung auf die Karten berechnen und prüfen, 2 bis 5 min
powershell -ExecutionPolicy Bypass -File scripts\Test-Model.ps1            # ein Profil, etwa 30 s
powershell -ExecutionPolicy Bypass -File scripts\Benchmark-Models.ps1      # alle Profile, etwa 10 bis 40 min
```

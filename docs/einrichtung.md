# Einrichtung

Neuaufbau auf einem frischen Rechner und Überblick, welche Datei was einstellt.

## Voraussetzungen

- Windows mit NVIDIA-Grafikkarte(n), zusammen mindestens 24 GB VRAM für das 27B-Modell mit
  64k Kontext. Aktueller Treiber (für das Paket `win-cuda-13.5-x64`; ältere Treiber:
  `win-cuda-12.4-x64` in `config\server.json`).
- Claude Code (`claude`), Python 3 (nur für die Prüfungen des Benchmarks), VS Code (nur für
  Continue).

## Neuaufbau in sechs Schritten

Aus dem Projektordner, jeweils mit `powershell -ExecutionPolicy Bypass -File`:

1. **Pfade prüfen:** `config\server.json` öffnen und `installRoot` und `modelsDir` an den
   Rechner anpassen (ein Laufwerk mit etwa 40 GB Platz).
2. **llama.cpp installieren:** `scripts\Install-LlamaCpp.ps1`. Am Ende listet das Skript
   die erkannten Grafikkarten auf.
3. **Modelldateien beschaffen** und mit `scripts\Add-Model.ps1` in den Modellordner legen.
   Die Quellen stehen im Feld `source` jedes Profils in `config\models.json`, das Vorgehen
   in [modelle.md](modelle.md). Die Dateinamen müssen zu `file` im Profil passen.
4. **Starten und prüfen:** `scripts\Test-Setup.ps1` (Konfiguration und Dateien), dann
   `scripts\Start-Server.ps1` und `scripts\Test-Model.ps1`. Erwartet: `tool calling: OK`
   und beide Karten belegt. Beim ersten Start entsteht der Schlüssel des Servers
   ([sicherheit.md](sicherheit.md)).
5. **Befehl einrichten:** `scripts\Install-Path.ps1`, danach Terminal oder VS Code neu
   starten. `claude-local` funktioniert dann in jedem Ordner.
6. **Continue (optional):** `scripts\Install-Continue.ps1`, danach VS Code neu starten.

Bei einer anderen Grafikkarten-Ausstattung müssen `tensor-split` und `device` in
`config\models.json` angepasst werden ([modelle.md](modelle.md), [gpu-tuning.md](gpu-tuning.md)).

## Welche Datei stellt was ein

| Datei | Inhalt | Beschreibung |
|---|---|---|
| `config\server.json` | llama-server: Ort, Version, Adresse, Grenzen | [backend.md](backend.md) |
| `config\models.json` | Modellprofile: Datei, Kontext, GPU-Aufteilung, Sampling | [modelle.md](modelle.md) |
| `config\templates\*.jinja` | angepasste Chat-Vorlagen | [modelle.md](modelle.md) |
| `config\agent.json` | Claude Code: Standardmodell, Kurznamen, Auswahl, Regeln | [agent.md](agent.md) |
| `config\entwicklungsregeln.md` | Arbeitsregeln für das lokale Modell | [agent.md](agent.md) |
| `config\continue.config.yaml` | Continue: Chat- und Autocomplete-Modelle | unten |
| `config\benchmark.json` | Profile und Aufgaben des Benchmarks | [erweitern.md](erweitern.md) |
| `config\guard.json` | Schutzregeln für Werkzeug-Aufrufe des lokalen Modells | [sicherheit.md](sicherheit.md) |

## Continue (Chat und Autocomplete im Editor)

`scripts\Install-Continue.ps1` installiert die Erweiterung, kopiert
`config\continue.config.yaml` nach `%USERPROFILE%\.continue\config.yaml` (eine vorhandene,
abweichende Datei wird gesichert), trägt dabei den Schlüssel des Servers ein und prüft, dass
jedes genannte Modell ein Profil ist. Nach einem neuen Schlüssel das Skript erneut
ausführen.

- Chat nutzt `local-coder` oder `local-fast` über die OpenAI-kompatible Schnittstelle.
- Autocomplete nutzt `qwen2.5-coder-1.5b-base` über die Schnittstelle `/completion`. Das
  Modell liegt allein auf der RTX 3060 und passt neben jedes der großen Modelle.
- Der Server muss laufen (`scripts\Start-Server.ps1`).
- Stand 2026-11-15: Die Schnittstellen sind mit direkten Anfragen geprüft, die Bedienung
  in VS Code selbst nach dem Umbau auf llama.cpp noch nicht, auch nicht mit dem Schlüssel
  des Servers. Meldet Continue Fehler 401, schickt es den Schlüssel nicht mit
  ([backend.md](backend.md), Fehlersuche).

## Was von Ollama übrig ist

Nichts. Bis 2026-11-14 lief das Projekt über Ollama; am selben Tag wurde Ollama
deinstalliert:

- Programm, Modellordner `E:\Ollama` (64 GB) und `%USERPROFILE%\.ollama` sind entfernt,
  ebenso der Autostart-Eintrag von Ollama.
- Die Benutzer-Variablen `OLLAMA_*` und `LLAMA_ARG_TENSOR_SPLIT` sind gelöscht.
- Die damals übernommenen GGUF-Dateien lagen als Hardlinks in `E:\LlamaCpp\models` und
  sind erhalten geblieben.

Die alten Skripte und Einstellungen stehen in der Git-Historie vor der ersten öffentlichen Version (bis Commit `fbb8c80`, nicht veröffentlicht).

## Autostart

`llama-server` startet nicht mit Windows. Es gibt keinen Dienst, keinen Autostart-Eintrag
und keine geplante Aufgabe. Der Server läuft erst, wenn `claude-local` oder
`scripts\Start-Server.ps1` ihn startet, und bis `scripts\Stop-Server.ps1` oder zum
Abmelden.

## Fehlersuche

Backend: [backend.md](backend.md). Agent: [agent.md](agent.md). Darüber hinaus:

| Symptom | Ursache und Abhilfe |
|---|---|
| `claude-local` wird nicht gefunden | Terminal oder VS Code neu starten. Sonst `scripts\Install-Path.ps1` ausführen. |
| Agent bearbeitet keine Dateien, schreibt nur Text | Modell beherrscht keine Tool-Calls. `Test-Model.ps1 -Model <name>` muss `tool calling: OK` zeigen. |
| Agent vergisst den Anfang der Sitzung | Kontext voll. Neue Sitzung oder `/clear`. |
| Skript bricht mit Zeichensalat in Meldungen ab | Eine `.ps1`-Datei enthält Nicht-ASCII-Zeichen. Windows PowerShell 5.1 liest Dateien ohne BOM als ANSI. |

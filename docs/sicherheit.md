# Schutz des eigenen Rechners

Das lokale Modell lehnt nichts ab, auch keine Anweisung, die in einer gelesenen Datei oder
Webseite versteckt ist, und es macht Fehler. Der Schutz liegt deshalb außerhalb des
Modells. Er hat ein einziges Ziel: **diesen Rechner und die eigenen Daten** vor Schaden zu
bewahren.

Zwei Dinge tut er ausdrücklich nicht:

- Er bewertet nicht, woran das Modell arbeitet. Es gibt keine Regel zu Inhalten, Themen
  oder Zielen außerhalb des eigenen Rechners.
- Er schränkt die normale Arbeit nicht ein. Alles im Projektordner bleibt frei: Dateien
  anlegen, ändern, löschen, Programme und Tests starten, Pakete installieren, committen,
  pushen.

## Die vier Teile

| Teil | Schützt vor | Wo eingestellt |
|---|---|---|
| Schlüssel für den Server | Webseiten im Browser und andere Programme, die den Server benutzen | `config\server.json` |
| Wächter vor jedem Werkzeug-Aufruf | zerstörerischen Befehlen, Zugriff auf Zugangsdaten | `config\guard.json` |
| Git-Hinweis beim Start | Änderungen, die sich nicht zurücknehmen lassen | `config\agent.json` |
| Prüfskripte | Fehlern in der Konfiguration, die den Schutz unbemerkt abschalten | `scripts\Test-Setup.ps1`, `scripts\Test-Guard.ps1` |

## Schlüssel für den Server

`llama-server` hört nur auf `127.0.0.1`. Ohne Schlüssel konnte ihn trotzdem jede Webseite
ansprechen, die im Browser geöffnet ist: Modelle laden, Anfragen stellen, Antworten lesen.
Der Server meldete das beim Start selbst (`no API key is set and CORS allows all origins`).

- **`requireApiKey`**: Der Server verlangt bei jeder Anfrage einen Schlüssel. Er wird beim
  ersten Start erzeugt (32 Zufallsbytes) und liegt in `<installRoot>\run\api-key.txt`,
  außerhalb des Repositorys. Die Skripte, `claude-local` und Continue schicken ihn mit.
- **`corsOrigins`** = `localhost`: Eine fremde Webseite darf Antworten des Servers nicht
  lesen.
- Der Schlüssel wird über die Umgebung übergeben, nicht über die Befehlszeile. So gilt er
  auch für die Modell-Prozesse, die der Server auf eigenen Ports startet, und steht in
  keiner Prozessliste.

Gemessen: Anfragen ohne Schlüssel bekommen `401`, am Server und am Modell-Prozess.
`/health` bleibt ohne Schlüssel erreichbar.

**Neuen Schlüssel erzeugen:** Server stoppen, `api-key.txt` löschen, `Start-Server.ps1`,
dann `Install-Continue.ps1` (trägt den Schlüssel in die Konfiguration von Continue ein).

## Wächter vor jedem Werkzeug-Aufruf

Unter Windows laufen die Befehle beider Agenten ohne Sandbox. Vor jedem Aufruf von `Bash`,
`PowerShell`, `Read`, `Edit`, `Write`, `Glob` und `Grep` entscheidet deshalb ein Wächter
nach festen Regeln aus `config\guard.json`, und das Modell kann ihn nicht überreden. Die
Regeln stehen in `scripts\hooks\GuardRules.ps1`, gemeinsam für beide Agenten:

- **Unzensiert** prüft im eigenen Prozess, bevor ein Werkzeug läuft, in jedem Rechte-Modus
  zuerst ([unzensiert.md](unzensiert.md)).
- **`claude-local`** übergibt Claude Code einen Hook (`PreToolUse`), der für jeden Aufruf
  `scripts\hooks\Guard-Tool.ps1` als eigenen Prozess startet.

| Entscheidung | Wirkung |
|---|---|
| keine | Der Aufruf läuft. Das ist der Normalfall. |
| `ask` | Du wirst gefragt und entscheidest. In Läufen ohne Nutzer (`-p`, Benchmark) zählt das als Nein. |
| `deny` | Der Aufruf läuft nicht. Das Modell bekommt die Begründung. |

### Was gesperrt ist (`deny`)

| Regel | Inhalt |
|---|---|
| `delete-system` | Rekursives Löschen eines Laufwerks, des Benutzerordners und seiner Hauptordner, des Projekt- und des Installationsordners als Ganzes (`%CLAUDE_LOCAL_PROJECTS%`, `%CLAUDE_LOCAL_ROOT%`, siehe unten), und alles in Windows- und Programmordnern |
| `disk-format` | Formatieren, Partitionieren, rohes Überschreiben eines Laufwerks |
| `boot-and-backups` | Startkonfiguration, Schattenkopien, Sicherungen löschen, freien Speicher überschreiben |

### Wobei du gefragt wirst (`ask`)

| Regel | Inhalt |
|---|---|
| `delete-project` | den ganzen Projektordner oder dessen `.git` löschen |
| `delete-outside` | rekursives Löschen außerhalb des Projektordners (außer im Temp-Ordner) |
| `git-discard` | `git reset --hard`, `git clean -f`, `git checkout -- .`, `git branch -D` und ähnliche |
| `git-force-push` | `git push --force`, `--delete`, `--mirror` (`--force-with-lease` ist frei) |
| `download-and-run` | Laden aus dem Netz mit sofortigem Ausführen (`curl … \| sh`, `irm … \| iex`) |
| `registry-change` | Änderungen an der Registrierung |
| `security-off` | Virenschutz, Firewall, Benutzerkonten, Dienste |
| `autostart` | geplante Aufgaben, Dienste, Autostart-Einträge |
| `shutdown` | Herunterfahren, Neustart, Abmelden |
| `credential-tools`, `secret-paths`, `secret-files` | SSH-Schlüssel, Anmeldedaten von Cloud-Diensten, GitHub und Claude, Browser-Profile, Passwort-Datenbanken (`secretPaths`, `secretFileNames`). Öffentliche Schlüssel (`*.pub`) sind frei. |
| `guard-files` | Änderungen an `config\guard.json`, `config\machine.json`, am Wächter selbst und an den Einstellungen von Claude Code |

Was davon in einer Sitzung vorkam, steht in `<installRoot>\logs\guard.log`.

**Ordner dieses Rechners.** `config\guard.json` nennt keine festen Laufwerke. Den
Installationsordner und den Projektordner schreibt sie als `%CLAUDE_LOCAL_ROOT%` und
`%CLAUDE_LOCAL_PROJECTS%`. `scripts\_common.ps1` setzt beide Variablen aus den
Einstellungen des Rechners, und der Wächter bekommt sie über Claude Code mit; startet man
ihn von Hand, liest `scripts\hooks\HookEnvironment.ps1` sie selbst nach. Ein Eintrag mit
einer unbekannten Variable fällt weg, die übrigen Regeln gelten weiter. `Test-Guard.ps1`
setzt feste Beispielordner (`machine` in `tests\guard-cases.json`), damit die Fälle auf
jedem Rechner dasselbe ergeben.

### Regeln ändern

`config\guard.json` bearbeiten, danach `scripts\Test-Guard.ps1`. Gilt ab der nächsten
Sitzung.

- **Eine Regel stört:** `decision` von `deny` auf `ask` setzen oder den Eintrag entfernen.
- **Ein weiterer Ordner soll geschützt sein:** unter `criticalPaths` (als Ganzes nicht
  löschbar) oder `secretPaths` (Zugriff nur nach Rückfrage) eintragen.
- **Neue Regel für Befehle:** Eintrag unter `commandRules` mit `id`, `decision`, `pattern`
  (regulärer Ausdruck, Groß- und Kleinschreibung egal) und `reason`. Dazu Fälle in
  `tests\guard-cases.json`: mindestens einen, der greifen muss, und einen ähnlichen, der
  frei bleiben muss.
- **Abschalten:** `"enabled": false`.

`Test-Guard.ps1` gibt jeden Fall aus `tests\guard-cases.json` so an den Wächter, wie Claude
Code es tut. Der erste Block der Fälle sind normale Arbeitsschritte, die frei bleiben
müssen; er verhindert, dass eine neue Regel die Arbeit behindert.

### Grenzen

- **Kein Ersatz für eine Sandbox.** Der Wächter erkennt Befehle an ihrer Schreibweise. Er
  hält Fehler und direkte Versuche auf, nicht einen Befehl, der absichtlich verschleiert
  ist (zusammengesetzt aus Variablen, in einem Skript versteckt, das erst geschrieben und
  dann gestartet wird). Gemessen am 2026-11-15: Auf einen gesperrten Befehl hin suchte das
  Modell von sich aus eine andere Schreibweise, die nicht gesperrt war. In dem Fall war
  sie harmlos; verlassen kann man sich darauf nicht. Wirklich einsperren lassen sich
  Befehle nur in WSL2 ([roadmap.md](roadmap.md), S6).
- **Löschziele in Variablen** (`rm -rf "$DIR"`) kann der Wächter nicht auflösen; sie
  bleiben frei, sonst wäre normale Arbeit ständig unterbrochen.
- **Kosten:** bei `claude-local` etwa 0,3 s je Werkzeug-Aufruf (Start von PowerShell,
  gemessen 280 ms), bei Unzensiert 2,7 ms (im eigenen Prozess, gemessen).
- **Schlägt der Wächter selbst fehl** (kaputte `guard.json`), wirst du bei jedem Aufruf
  gefragt, statt dass alles ungeprüft läuft. `scripts\Test-Setup.ps1` zeigt die Ursache.
- **`.env`-Dateien im Projekt sind nicht geschützt.** Das Modell braucht sie oft für die
  Arbeit, und es läuft lokal. Wer das anders will, trägt `.env` unter `secretFileNames`
  ein.
- Der Wächter gilt für `unzensiert` und `claude-local`. Das normale `claude` ist unberührt.

## Git-Hinweis beim Start

`unzensiert` und `claude-local` melden beim Start in einem Terminal, wenn der Ordner kein Git-Repository
ist oder nicht gesicherte Änderungen enthält (`gitCheck` in `config\agent.json`). Mit einem
Commit vor der Sitzung lässt sich alles, was das Modell ändert, mit `git diff` ansehen und
mit `git checkout` zurücknehmen. Bei umgeleiteter Ausgabe (`-p` in Skripten) erscheint der
Hinweis nicht.

## Prüfskripte

| Skript | Prüft | Dauer |
|---|---|---|
| `Test-Setup.ps1` | Konfigurationsdateien gültig und zueinander passend, Skripte lesbar (ASCII, Syntax), Modelldateien und Vorlagen vorhanden, Wächter antwortet | wenige Sekunden |
| `Test-Guard.ps1` | alle Fälle aus `tests\guard-cases.json` | etwa 25 s |

Beide brauchen keine Grafikkarte und enden bei einem Fehler mit Exit-Code 1.

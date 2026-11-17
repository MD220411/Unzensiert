# Planer: Modelle auf Karten und Hauptspeicher verteilen

Der Planer (`scripts\Plan-Models.ps1`, Rechnung in `scripts\lib\Planner.ps1`) rechnet für
jeden Rechner aus, wie ein Modell am schnellsten auf seine Grafikkarten und den
Hauptspeicher verteilt wird: wie viele Schichten auf welche Karte, in welcher Reihenfolge,
welche Experten in den Hauptspeicher, wohin der Bild-Encoder und welche Kontextgröße. Der
Installer ruft ihn nach dem Download auf; das Ergebnis steht in `config\machine.json`.

Ohne Planer verteilt llama.cpp selbst (`--fit`). Das sorgt dafür, dass alles passt, aber
nicht dafür, dass es schnell ist: Auf dem Entwicklungsrechner (RTX 5070 Ti + RTX 3060)
erzeugte `local-coder` damit 44 Tokens/s, mit der von Hand gefundenen Aufteilung 70/30
etwa 60, mit dem Plan 66 bis 71 (gemessen, siehe unten).

## Die Rechnung

**Speicher.** Für eine bestimmte Verteilung schätzt llama.cpp selbst, wie viel MiB
Gewichte, Kontext und Rechenpuffer auf jedem Gerät landen
(`llama-fit-params --fit-print on`, etwa eine halbe Sekunde je Aufruf). Der Planer zählt
dazu, was diese Schätzung nicht kennt, und vergleicht mit dem freien Speicher, den
llama.cpp meldet:

| Zuschlag | Wert | Herkunft |
|---|---|---|
| Reserve je Karte | 1024 MiB | CUDA-Kontext des Servers (650 MiB gemessen, 540 davon fehlen schon im gemeldeten freien Speicher) und Platz für die Messprozesse, die der Router nach jedem Start kurz für die anderen Modelle startet (je etwa 550 MiB). Mit 512 MiB stürzte ein Modell in diesem Moment ab. |
| MTP-Vorausraten | 1408 MiB auf der Karte mit den letzten Schichten | eigener Kontext und Puffer des Entwurfs, gemessen 1375 MiB bei 128k |
| Bild-Encoder | Dateigröße + 256 MiB | auf der Karte, auf der danach noch genug frei ist, sonst auf dem Prozessor |

**Tempo.** Für jedes erzeugte Token wird jedes Gewicht einmal gelesen, bei einem
Mixture-of-Experts-Modell nur die aktiven Experten (8 von 256). Die Zeit je Token ist
deshalb ungefähr

    t = Σ über alle Geräte (gelesene MiB auf dem Gerät × Mikrosekunden je MiB des Geräts)

Die gelesenen MiB ergeben sich aus der Schätzung von llama.cpp: Gewichte auf dem Gerät,
abzüglich der nicht aktiven Experten und der Token-Einbettung, die der Hauptspeicher nur
hält. Die Mikrosekunden je MiB misst der Planer einmal je Modell (**Kalibrierung**, etwa
eine halbe Minute) mit `llama-bench`: einmal nur auf dem Prozessor, dann je Karte einmal
„diese Karte zuerst gefüllt“. Jeder Lauf ist eine Gleichung, die Unbekannten sind die
Mikrosekunden je MiB der Karten; ein kleines lineares Gleichungssystem liefert sie. Das
braucht keine Tabelle mit Kartendaten und gilt auch für AMD und Intel.

Auf dem Entwicklungsrechner ergab das 1,38 µs/MiB für die RTX 5070 Ti (≈ 760 GB/s),
3,57 µs/MiB für die RTX 3060 (≈ 294 GB/s) und 19,9 µs/MiB für den Hauptspeicher. Das
Verhältnis der Karten (2,6) trifft das der Herstellerangaben (896 zu 360 GB/s, 2,5). Zwei
Aufteilungen, die nur Gewichte zwischen den Karten verschieben, ergaben dieselbe Differenz
(2,16 und 2,10 µs je verschobenem MiB).

**Suche.** Für jede Kontextgröße (128k, 96k, 64k, 32k):

1. Die schnellste Karte wird zuerst gefüllt, so weit es passt (Halbierungssuche über die
   Zahl der Schichten, jede Probe mit der Schätzung von llama.cpp), dann die nächste. Die
   schnellste Karte steht in der Geräteliste (`--device`) zuletzt: So bekommt sie die
   Ausgabeschicht und die MTP-Schicht, die beim Vorausraten mehrmals je Token gelesen
   werden.
2. Passt nicht alles auf die Karten, wandern bei einem Mixture-of-Experts-Modell zuerst
   Experten in den Hauptspeicher (`--n-cpu-moe`, so wenige wie nötig): Von dort werden je
   Token nur die wenigen aktiven gelesen. Erst danach, und bei dichten Modellen gleich,
   bleiben die ersten Schichten im Hauptspeicher.
3. Die Zeit je Token wird nach der Formel oben vorhergesagt.

Gewählt wird die größte Kontextgröße ab `minCtx` (64k), deren Zeit höchstens
`speedTolerance` (15 %) über der schnellsten liegt. Mehr Kontext ist etwas Tempo wert: Im
Benchmark bestand die Aufgabe `longcontext` erst mit 128k ([modellwahl.md](modellwahl.md)).

**Ergebnis.** In `config\machine.json` unter `models.<profil>.args`: `ctx-size`,
`gpu-layers`, `device` (langsamste Karte zuerst), `tensor-split` (Einheiten je Karte; die
Ausgabeschicht zählt als eine Einheit), `n-cpu-moe`, `mmproj-device` oder
`mmproj-offload: false` und `fit: off`, damit llama.cpp nichts mehr verschiebt. Daneben
`plans.<profil>` (Vorhersage, gemessenes Tempo) und `calibration.<profil>` (die Messläufe).

## Benutzen

```
powershell -ExecutionPolicy Bypass -File scripts\Plan-Models.ps1            # alle geladenen Agenten-Modelle
powershell -ExecutionPolicy Bypass -File scripts\Plan-Models.ps1 -Verify    # danach laden und testen
... -Model local-fast    nur dieses Profil
... -Recalibrate         neu messen (sonst nur, wenn sich die Karten geändert haben)
... -Show                gespeicherte Pläne anzeigen
```

Der Planer stoppt den Server, damit die Karten leer sind. Nach einem Wechsel der
Grafikkarte oder wenn dauerhaft andere Programme Grafikspeicher belegen, neu planen.
`-Verify` lädt jedes Modell und prüft es mit `Test-Model.ps1`; lädt es nicht oder stürzt
der Modellprozess unter einer Anfrage ab, plant es mit 1 GB mehr Reserve je Karte neu
(höchstens zweimal) und merkt sich die Reserve in `machine.json` (`planner.reserveMiB`).

Zum Messen anderer Ausstattungen auf diesem Rechner: `scripts\Measure-Setup.ps1 -Planned`
macht nur bestimmte Karten sichtbar und lässt den Planer genau für diese rechnen.

## Gemessen

Alle Läufe am 2026-11-17 auf dem Entwicklungsrechner, mit `Test-Model.ps1` (Tempo mit
MTP-Vorausraten; es schwankt mit der Trefferquote des Entwurfs um einige Prozent), dazu
das Einlesen von 26.177 Tokens. Tool-Calls und Bild-Eingabe in allen Läufen OK. Rohwerte:
`logs\model-tests.log`.

| Karten | Modell, Kontext | `--fit` | Hand | Planer |
|---|---|---|---|---|
| RTX 5070 Ti + RTX 3060 | `local-coder`, 128k | 44 Tok./s | 58,5 / 61,8 | **65,7 / 70,7** |
| RTX 5070 Ti allein | `local-coder`, 64k | 20,9 Tok./s, Prompt 572/s | | **21,8**, Prompt 591/s |
| RTX 5070 Ti allein | `local-fast`, 64k | 97,1 Tok./s, Prompt 775/s | | **105,7**, Prompt 844/s |
| RTX 3060 allein | `local-fast`, 64k | 62,2 Tok./s, Prompt 244/s | | **65,0**, Prompt 260/s |

Ohne Vorgabe wählte der Planer: auf der RTX 5070 Ti allein für `local-coder` 96k
(18,7 Tok./s), auf der RTX 3060 allein für `local-fast` 128k (58,2 Tok./s), auf der
RTX 3060 mit 4 GB frei gehalten (≈ 8-GB-Karte) 128k (53,6 Tok./s).

Der Gewinn auf zwei Karten kommt vor allem aus der Reihenfolge: Ausgabe- und MTP-Schicht
auf der schnellen Karte. Die Handeinstellung 70/30 mit umgekehrter Reihenfolge lud gar
nicht mehr; erst die Rechnung findet die passende Aufteilung (38 bzw. 37 Schichten auf
der RTX 5070 Ti). Auf einer Karte bringt der Plan 4 bis 9 %: Bild-Encoder auf den
Prozessor, genau so viele Experten ausgelagert wie nötig.

Die vorhergesagten Werte des Planers (ohne MTP, etwa 28 Tok./s für den Plan auf zwei
Karten) sind niedriger als die gemessenen mit MTP; für die Wahl zählen nur die
Verhältnisse zwischen den Varianten.

## Grenzen

- **Windows lagert still aus.** Ist eine Karte voll, verschiebt der NVIDIA-Treiber Speicher
  in den Hauptspeicher (Sysmem Fallback), ohne Fehler, nur langsamer. Die belegte Menge
  steht dann an einer festen Grenze (RTX 5070 Ti: 15,58 GB). Die Reserve soll das
  verhindern; `Plan-Models.ps1 -Verify` prüft nur, ob das Modell läuft, nicht ob es
  auslagert.
- **Mixture-of-Experts kalibriert schlecht.** Auf dem Prozessor ist ein solches Modell eher
  durch Rechnen als durch Lesen begrenzt; die Werte der Karten aus seinen Läufen sind
  unzuverlässig (gemessen: 0,55 µs/MiB für die RTX 3060, unmöglich). Für die Wahl auf einer
  Karte spielt das keine Rolle, bei mehreren Karten übernimmt der Planer die Kartenwerte
  aus der Kalibrierung eines dichten Modells auf denselben Karten, wenn es eine gibt.
  Unplausible Werte (≤ 0 oder langsamer als der Hauptspeicher) ersetzt er durch ein
  Zwölftel des Hauptspeicherwerts und meldet das.
- **Die Formel kennt keine Kontext-Tiefe.** Bei langem Gespräch liest jedes Token auch den
  Kontext-Cache; die Vorhersage gilt für ein kurzes Gespräch.
- **Ungeprüft:** echte Rechner mit anderen Karten, AMD und Intel über Vulkan (die Rechnung
  ist dieselbe, `Get-GpuMemory` zeigt dort aber nichts), mehr als zwei Karten.

## Einstellungen (`config\planner.json`)

| Schlüssel | Wert | Zweck |
|---|---|---|
| `reserveMiB` | `1024` | je Karte frei gehalten, siehe oben |
| `mtpReserveMiB` | `1408` | Zuschlag für das MTP-Vorausraten auf der Karte mit den letzten Schichten |
| `ramReserveGiB` | `6` | Hauptspeicher für Windows und andere Programme |
| `mmprojExtraMiB` | `256` | Rechenpuffer des Bild-Encoders |
| `ctxCandidates` | `131072, 98304, 65536, 32768` | geprüfte Kontextgrößen |
| `minCtx` | `65536` | kleiner nur, wenn nichts anderes passt |
| `speedTolerance` | `0.15` | so viel langsamer darf ein größerer Kontext sein |
| `bench` | `tokens 32, repetitions 2, cpuTokens 12` | Messläufe der Kalibrierung |

Ein Rechner kann einzelne Werte in `config\machine.json` unter `planner` überschreiben.
Nach einer Änderung `scripts\Plan-Models.ps1 -Verify` und `scripts\Test-Install.ps1`.

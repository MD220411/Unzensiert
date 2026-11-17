# Giesser

Bewässerungssteuerung für einen Raspberry Pi: Liegt die Bodenfeuchte unter der Schwelle
oder drückt jemand den Taster, läuft die Pumpe für eine feste Zeit. Meldet der
Regensensor Regen, wird nicht gegossen, auch nicht über den Taster.

## Voraussetzungen

Raspberry Pi mit 40-poliger Stiftleiste, Python 3.10 oder neuer, `RPi.GPIO` (auf dem Pi
vorinstalliert). Die Tests laufen ohne Pi.

## Benutzung

```python
from giesser import hardware, steuerung
hw = hardware.Hardware(RPi.GPIO)
steuerung.zyklus(hw, feuchte=28.0)
```

## Verdrahtung

Nummern nach BCM, dazu der Pin der Stiftleiste. Einzelheiten und Belegung der ganzen
Leiste: `docs/verdrahtung.md`.

| Teil | GPIO | Pin |
|---|---|---|
| Pumpe (Relais IN1) | GPIO23 | 16 |
| Regensensor (offener Kollektor) | GPIO17 | 11 |
| Taster (gegen Masse) | GPIO22 | 15 |
| Status-LED | GPIO27 | 13 |

## Einstellungen

| Datei | Schlüssel | Bedeutung |
|---|---|---|
| `config/pins.json` | `pumpe`, `regensensor`, `taster`, `led` | GPIO-Nummern (BCM) |
| `config/settings.json` | `schwelle_prozent` | unter dieser Bodenfeuchte wird gegossen |
| `config/settings.json` | `giessdauer_s` | so lange läuft die Pumpe |

## Prüfen

```
python -m unittest discover -s tests -t .
python scripts/check_facts.py
```

`facts/facts.json` enthält die Pinbelegung als eine Quelle der Wahrheit;
`scripts/check_facts.py` meldet jede Stelle in Doku und Code, die davon abweicht.

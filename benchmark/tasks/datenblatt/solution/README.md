# Klimalogger

Liest Temperatur und Luftfeuchte von einem I2C-Sensor und gibt sie als CSV-Zeile aus.

## Voraussetzungen

Python 3.10 oder neuer. Für einen echten I2C-Bus eine Klasse nach dem Muster von
`klima.bus.Bus` (zum Beispiel über `smbus2`); die Tests brauchen keine Hardware.

## Benutzung

```python
from klima import logger
print(logger.csv_line(bus))   # 2026-11-17T10:00:00;21.50;48.20
```

## Einstellungen (`config/settings.json`)

| Schlüssel | Bedeutung |
|---|---|
| `sensor` | Treiber des angeschlossenen Sensors: `hx5` oder `hx7` |

## Unterstützte Sensoren

| Sensor | Treiber | Datenblatt |
|---|---|---|
| HX-5 | `klima/hx5.py` | `docs/datenblatt-hx5.md` |
| HX-7 | `klima/hx7.py` | `docs/datenblatt-hx7.md` |

## Aufbau

| Datei | Aufgabe |
|---|---|
| `klima/bus.py` | Schnittstelle des I2C-Busses, Fehlerklasse `SensorError` |
| `klima/hx5.py` | Treiber HX-5: `probe(bus)`, `read_measurement(bus)` |
| `klima/hx7.py` | Treiber HX-7, gleiche Schnittstelle; startet jede Messung und wartet auf DRDY |
| `klima/logger.py` | wählt den Treiber nach `sensor`, formatiert die CSV-Zeile |
| `facts/facts.json` | Fakten aus den Datenblättern, mit Quelle |

## Tests

```
python -m unittest discover -s tests -t .
```

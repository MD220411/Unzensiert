# HX-5 Temperatur- und Feuchtesensor – Datenblatt (Auszug)

Revision 2.1

## Schnittstelle

- I2C, bis 400 kHz, 7-Bit-Adresse **0x44** (fest).
- Der Sensor misst fortlaufend (alle 100 ms). Die Register enthalten immer den letzten
  Messwert.

## Register

| Adresse | Name | Zugriff | Inhalt |
|---|---|---|---|
| 0x00 | TEMP | R, 2 Byte | Temperatur, Rohwert, höherwertiges Byte zuerst |
| 0x02 | HUM | R, 2 Byte | relative Feuchte, Rohwert, höherwertiges Byte zuerst |
| 0xFE | ID | R | Kennung, immer 0x55 |

Vor der ersten Messung (etwa 120 ms nach dem Einschalten) lesen beide Register 0xFFFF.

## Umrechnung

- Temperatur: T [°C] = Rohwert × 0,01 − 40
- Feuchte: RH [%] = Rohwert × 0,01, höchstens 100

## Elektrisch

| Größe | Wert |
|---|---|
| Versorgung VDD | 2,4 bis 5,5 V |
| Stromaufnahme | 150 µA |

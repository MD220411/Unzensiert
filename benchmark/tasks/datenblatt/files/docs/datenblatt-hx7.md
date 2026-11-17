# HX-7 Temperatur- und Feuchtesensor – Datenblatt (Auszug)

Revision 1.3. Der HX-7 ist pinkompatibel zum HX-5 und braucht im Mittel 80 % weniger
Strom, weil er nur auf Anforderung misst.

## 1 Merkmale

- Temperatur −40 bis +125 °C, Genauigkeit ±0,2 °C
- Relative Feuchte 0 bis 100 %, Genauigkeit ±1,5 %
- I2C bis 1 MHz, Registerzugriff mit automatischem Weiterzählen der Adresse
- Einzelmessung auf Befehl, danach Ruhezustand

## 2 Anschlüsse

| Pin | Name | Funktion |
|---|---|---|
| 1 | VDD | Versorgung |
| 2 | SCL | I2C-Takt |
| 3 | SDA | I2C-Daten |
| 4 | ADDR | Adresswahl, siehe 3 |
| 5 | GND | Masse |

## 3 I2C-Adresse

Die 7-Bit-Adresse hängt vom Pin ADDR ab:

| ADDR | Adresse |
|---|---|
| an GND | 0x3A |
| an VDD | 0x3B |

Auf dem Modul „HX-7 Breakout“ liegt ADDR fest an GND.

## 4 Register

| Adresse | Name | Zugriff | Inhalt |
|---|---|---|---|
| 0x0F | WHO_AM_I | R | Kennung, immer 0x67 |
| 0x10 | CTRL | W | Befehl: 0x5A startet eine Einzelmessung, 0xA5 setzt den Sensor zurück |
| 0x11 | STATUS | R | Bit 0 DRDY: Messwerte bereit. Bit 1 ERR: Messung fehlgeschlagen. Bits 2 bis 7 reserviert |
| 0x12 | T_L | R | Temperatur, niederwertiges Byte |
| 0x13 | T_H | R | Temperatur, höherwertiges Byte |
| 0x14 | H_L | R | Feuchte, niederwertiges Byte |
| 0x15 | H_H | R | Feuchte, höherwertiges Byte |

Ein Lesezugriff ab 0x12 über vier Byte liefert T_L, T_H, H_L, H_H.

## 5 Ablauf einer Messung

1. 0x5A nach CTRL schreiben.
2. STATUS lesen, bis DRDY gesetzt ist. Typische Messdauer 12 ms, höchstens 40 ms. Ist DRDY
   nach 50 ms nicht gesetzt, ist der Sensor defekt oder nicht angeschlossen.
3. Ist ERR gesetzt, sind die Messwerte ungültig.
4. Die vier Datenbytes ab 0x12 lesen. Das Lesen von H_H löscht DRDY.

Ohne Schritt 1 enthalten die Datenregister keine gültigen Werte.

## 6 Umrechnung

- Temperatur: T [°C] = Rohwert / 256 − 50
- Feuchte: RH [%] = Rohwert / 512

Bei Betauung liefert der Sensor Feuchtewerte über 100 %. Sie sind als 100 % auszugeben.

## 7 Elektrisch

| Größe | Wert |
|---|---|
| Versorgung VDD | 1,8 bis 3,6 V |
| Pegel an SCL, SDA, ADDR | höchstens VDD + 0,3 V |
| Stromaufnahme in Ruhe | 0,3 µA |
| Stromaufnahme während der Messung | 210 µA |

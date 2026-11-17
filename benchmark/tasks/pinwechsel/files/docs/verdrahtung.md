# Verdrahtung

Alle Nummern nach BCM (`GPIO.setmode(GPIO.BCM)`), dazu der Pin der 40-poligen Stiftleiste.

## Anschlüsse

| Teil | GPIO | Pin | Richtung | Hinweis |
|---|---|---|---|---|
| Pumpe (Relais IN1) | GPIO17 | 11 | Ausgang | Relaismodul aktiv high, Versorgung 5 V an Pin 2 |
| Taster (gegen Masse) | GPIO22 | 15 | Eingang | interner Pull-up, gedrückt = low |
| Status-LED | GPIO27 | 13 | Ausgang | über 330 Ohm gegen Masse |

```
 Pi Pin 11 (GPIO17) ----> Relais IN1 ----> Pumpe
 Pi Pin 15 (GPIO22) <---- Taster ----> GND
 Pi Pin 13 (GPIO27) ----> 330 Ohm ----> LED ----> GND
```

## Belegung der Stiftleiste

| Pin | Funktion | Pin | Funktion |
|---|---|---|---|
| 1 | 3,3 V | 2 | 5 V |
| 3 | GPIO2 (SDA) | 4 | 5 V |
| 5 | GPIO3 (SCL) | 6 | GND |
| 7 | GPIO4 | 8 | GPIO14 (TXD) |
| 9 | GND | 10 | GPIO15 (RXD) |
| 11 | GPIO17 | 12 | GPIO18 |
| 13 | GPIO27 | 14 | GND |
| 15 | GPIO22 | 16 | GPIO23 |
| 17 | 3,3 V | 18 | GPIO24 |
| 19 | GPIO10 (MOSI) | 20 | GND |
| 21 | GPIO9 (MISO) | 22 | GPIO25 |
| 23 | GPIO11 (SCLK) | 24 | GPIO8 (CE0) |
| 25 | GND | 26 | GPIO7 (CE1) |
| 27 | GPIO0 (ID_SD) | 28 | GPIO1 (ID_SC) |
| 29 | GPIO5 | 30 | GND |
| 31 | GPIO6 | 32 | GPIO12 |
| 33 | GPIO13 | 34 | GND |
| 35 | GPIO19 | 36 | GPIO16 |
| 37 | GPIO26 | 38 | GPIO20 |
| 39 | GND | 40 | GPIO21 |

# Fakten

`facts.json` ist die eine Quelle der Wahrheit für alles, was nicht aus diesem Projekt
selbst stammt: Adressen, Register, Umrechnungen und Grenzwerte aus Datenblättern. Jeder
Fakt steht hier genau einmal, mit seiner Quelle.

1. Erst hier nachsehen. Steht der Fakt hier, gilt dieser Wert.
2. Fehlt er, im Datenblatt nachlesen statt raten, dann mit Quelle eintragen.
3. Lässt er sich nicht belegen, mit `"status": "annahme"` eintragen und es sagen.

Felder je Fakt: `id`, `value`, `source` (Datei und Abschnitt), optional `status`.

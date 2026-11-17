# Fakten

`facts.json` ist die eine Quelle der Wahrheit für alles, was nicht aus diesem Projekt
selbst stammt: Pins und Spannungen, Namen von Funktionen und Konfigurationsschlüsseln
fremder Programme, Adressen, Grenzwerte aus Datenblättern, Versionen. Jeder Fakt steht hier
genau einmal, mit seiner Quelle. Der Prüfbefehl (`scripts\Check.ps1`, Schritt „Fakten“)
vergleicht ihn mit jeder Stelle in Dokumentation und Code.

## Regel

1. **Erst hier nachsehen.** Steht der Fakt in `facts.json`, gilt dieser Wert.
2. **Fehlt er, nachlesen statt raten:** im Datenblatt, in der Doku, im Quelltext oder in
   den Headern der Bibliothek, mit `--help`. Dann mit Quelle eintragen.
3. **Lässt er sich nicht belegen,** mit `"status": "annahme"` eintragen und dem Nutzer
   sagen, dass der Wert unbelegt ist. Der Prüfbefehl zeigt jede Annahme als `warn`.
4. **Ändert sich ein Fakt,** zuerst hier ändern, dann `scripts\Check.ps1` ausführen: Er
   nennt jede Datei, die noch den alten Wert hat.

## Aufbau

```json
{
  "devices": { "controller": { "board": "esp32" } },
  "facts": [
    {
      "id": "display.sid",
      "value": "GPIO17",
      "device": "controller",
      "direction": "out",
      "labels": ["SID"],
      "code": ["DISPLAY_PIN_SID"],
      "source": "Verdrahtung festgelegt vom Nutzer, docs/verdrahtung.md"
    },
    {
      "id": "display.spannung",
      "value": "5V",
      "code": ["DISPLAY_VCC"],
      "source": "Datenblatt ST7920, Abschnitt Electrical Characteristics"
    }
  ],
  "allow_unlisted_pins": [],
  "skip": []
}
```

| Feld | Bedeutung |
|---|---|
| `id` | eindeutiger Name des Fakts |
| `value` | der Wert. Pins als `GPIO<n>`; Zahlen mit Einheit wie `3.3V` |
| `source` | woher der Wert stammt: Datenblatt mit Abschnitt, Datei mit Zeile, Adresse der Doku, Vorgabe des Nutzers. Pflicht, außer bei `"status": "annahme"` |
| `status` | `belegt` (Standard) oder `annahme` |
| `device` | bei mehreren Geräten (Steuerung, Sensorknoten): zu welchem der Fakt gehört. Ein Pin darf je Gerät nur einmal vorkommen, außer alle Fakten dazu haben `"shared": true` |
| `direction` | bei Pins: `in`, `out` oder `io`; ein Ausgang auf einem Pin, der nur Eingang kann, ist ein Fehler |
| `labels` | bei Pins: Namen, unter denen der Pin in der Doku steht. `GPIO17 (SID` und `SID = GPIO17` müssen dann den Pin des Fakts nennen. Ein Label gehört zu genau einem Fakt |
| `code` | Namen im Code oder in Konfigurationsdateien (`#define`, Zuweisung, JSON-Schlüssel), die genau diesen Wert haben müssen |

Unter `devices` steht je Gerät das Platinenprofil (`board`), eine Datei in `boards\`.
Mitgeliefert: `esp32.json` (Pins, die es gibt, nur Eingang, belegt vom Flash,
Strapping-Pins; Quelle in der Datei). Ein neues Profil braucht ebenfalls eine Quelle.

`allow_unlisted_pins`: Pins, die in der Doku vorkommen dürfen, ohne ein Fakt zu sein (etwa
in einer Erklärung, welche Pins man meiden soll). `skip`: Dateien oder Ordner, die der
Abgleich überspringt.

Sobald ein Fakt ein Pin ist, muss jeder in Doku und Code genannte Pin (`GPIO17`,
`GPIO_NUM_17`) in `facts.json` stehen.

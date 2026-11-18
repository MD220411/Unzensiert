# Facts

`facts.json` is the one source of truth for everything that does not come from this project
itself: pins and voltages, names of other programs' functions and configuration keys,
addresses, limits from datasheets, versions. Every fact appears here exactly once, with its
source. The check command (`scripts\Check.ps1`, step "Facts") compares it with every place
in the documentation and the code.

## Rule

1. **Look here first.** If the fact is in `facts.json`, this value applies.
2. **If it is missing, look it up instead of guessing:** in the datasheet, the
   documentation, the source code or the headers of the library, with `--help`. Then add it
   with its source.
3. **If it cannot be confirmed,** add it with `"status": "assumption"` and tell the user that
   the value is unconfirmed. The check command shows every assumption as `warn`.
4. **When a fact changes,** change it here first, then run `scripts\Check.ps1`: it names
   every file that still has the old value.

## Format

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
      "source": "Wiring decided by the user, docs/wiring.md"
    },
    {
      "id": "display.voltage",
      "value": "5V",
      "code": ["DISPLAY_VCC"],
      "source": "Datasheet ST7920, section Electrical Characteristics"
    }
  ],
  "allow_unlisted_pins": [],
  "skip": []
}
```

| Field | Meaning |
|---|---|
| `id` | unique name of the fact |
| `value` | the value. Pins as `GPIO<n>`; numbers with a unit like `3.3V` |
| `source` | where the value comes from: datasheet with section, file with line, address of the documentation, decision of the user. Required, except with `"status": "assumption"` |
| `status` | `confirmed` (default) or `assumption` (projects from earlier versions: `belegt`, `annahme`) |
| `device` | with several devices (controller, sensor node): which one the fact belongs to. A pin may appear only once per device, unless all facts about it have `"shared": true` |
| `direction` | for pins: `in`, `out` or `io`; an output on a pin that can only be an input is an error |
| `labels` | for pins: names under which the pin appears in the documentation. `GPIO17 (SID` and `SID = GPIO17` must then name the pin of the fact. A label belongs to exactly one fact |
| `code` | names in the code or in configuration files (`#define`, assignment, JSON key) that must have exactly this value |

Under `devices` each device has its board profile (`board`), a file in `boards\`. Included:
`esp32.json` (pins that exist, input-only pins, pins used by the flash, strapping pins;
source in the file). A new profile needs a source as well.

`allow_unlisted_pins`: pins that may appear in the documentation without being a fact (for
example in an explanation of which pins to avoid). `skip`: files or folders the comparison
skips.

As soon as one fact is a pin, every pin named in documentation and code (`GPIO17`,
`GPIO_NUM_17`) must be in `facts.json`.

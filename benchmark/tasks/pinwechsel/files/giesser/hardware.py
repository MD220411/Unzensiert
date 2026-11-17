"""Access to pump, button and LED through an RPi.GPIO-like module.

The pin numbers (BCM) come from config/pins.json; DEFAULT_PINS is used when the file is
missing, for example on a fresh checkout.
"""
import json
import pathlib

PINS_FILE = pathlib.Path(__file__).resolve().parent.parent / "config" / "pins.json"
DEFAULT_PINS = {"pumpe": 17, "taster": 22, "led": 27}


def load_pins(path=PINS_FILE):
    """The pin numbers from config/pins.json, or DEFAULT_PINS if the file is missing."""
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        return dict(DEFAULT_PINS)


class Hardware:
    """Pump, button and status LED of the watering control."""

    def __init__(self, gpio, pins=None):
        self.gpio = gpio
        self.pins = pins or load_pins()
        gpio.setmode(gpio.BCM)
        gpio.setup(self.pins["pumpe"], gpio.OUT, initial=gpio.LOW)
        gpio.setup(self.pins["led"], gpio.OUT, initial=gpio.LOW)
        gpio.setup(self.pins["taster"], gpio.IN, pull_up_down=gpio.PUD_UP)

    def pumpe(self, an):
        """Switch the pump on (True) or off (False)."""
        self.gpio.output(self.pins["pumpe"], self.gpio.HIGH if an else self.gpio.LOW)

    def led(self, an):
        """Switch the status LED on or off."""
        self.gpio.output(self.pins["led"], self.gpio.HIGH if an else self.gpio.LOW)

    def taster_gedrueckt(self):
        """True while the button is pressed (it pulls the pin to ground)."""
        return self.gpio.input(self.pins["taster"]) == self.gpio.LOW

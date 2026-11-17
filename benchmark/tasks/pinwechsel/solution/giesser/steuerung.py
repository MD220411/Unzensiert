"""One control cycle: decide whether to water and run the pump."""
import json
import pathlib
import time

SETTINGS_FILE = pathlib.Path(__file__).resolve().parent.parent / "config" / "settings.json"


def load_settings(path=SETTINGS_FILE):
    """The settings from config/settings.json."""
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def giessen_noetig(feuchte, taster, settings, regen=False):
    """True if it does not rain and the soil is drier than the threshold or the button is pressed."""
    if regen:
        return False
    return taster or feuchte < settings["schwelle_prozent"]


def zyklus(hw, feuchte, settings=None, warten=time.sleep):
    """Run one cycle. Returns True if the pump ran.

    hw is a hardware.Hardware, feuchte the soil moisture in percent. While it rains the
    pump stays off, also when the button is pressed.
    """
    settings = settings or load_settings()
    if not giessen_noetig(feuchte, hw.taster_gedrueckt(), settings, hw.regnet()):
        return False
    hw.led(True)
    hw.pumpe(True)
    try:
        warten(settings["giessdauer_s"])
    finally:
        hw.pumpe(False)
        hw.led(False)
    return True

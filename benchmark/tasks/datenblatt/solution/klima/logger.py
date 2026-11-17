"""Selects the sensor driver from the settings and formats a measurement as a CSV line."""
import json
import pathlib
import time

from . import hx5, hx7

DRIVERS = {"hx5": hx5, "hx7": hx7}
SETTINGS = pathlib.Path(__file__).resolve().parent.parent / "config" / "settings.json"


def load_settings(path=SETTINGS):
    """The settings from config/settings.json as a dict."""
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def get_driver(name):
    """The driver module for a sensor name from the settings."""
    try:
        return DRIVERS[name]
    except KeyError:
        raise ValueError(f"unknown sensor {name!r}, known: {', '.join(sorted(DRIVERS))}") from None


def csv_line(bus, settings=None, now=None):
    """One measurement of the configured sensor as 'time;temperature;humidity'."""
    settings = settings or load_settings()
    values = get_driver(settings["sensor"]).read_measurement(bus)
    stamp = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(now))
    return f"{stamp};{values['temperature']:.2f};{values['humidity']:.2f}"

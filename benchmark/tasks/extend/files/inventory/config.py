"""Reads the settings of the inventory tool from config.json."""
import json
import pathlib

CONFIG_FILE = pathlib.Path(__file__).resolve().parent.parent / "config.json"


def load_config(path=None):
    """Return the settings as a dict."""
    with open(path or CONFIG_FILE, encoding="utf-8") as handle:
        return json.load(handle)

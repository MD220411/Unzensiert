"""Reads the settings of the program from config/settings.json."""
import json
import pathlib

SETTINGS_FILE = pathlib.Path(__file__).resolve().parent.parent / "config" / "settings.json"


def load_settings(path=SETTINGS_FILE):
    """Return the settings as a dictionary. Raises ValueError if the file is not valid JSON."""
    try:
        return json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise ValueError(f"{path} is not valid JSON: {error}") from error

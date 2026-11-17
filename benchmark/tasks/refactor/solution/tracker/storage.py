"""The data file of the tracker: the only place that reads and writes it."""
import json
import os
import tempfile


class StorageError(Exception):
    """Raised when the data file cannot be read as JSON."""


def empty_database():
    """Return a new empty database."""
    return {"tasks": [], "projects": [], "next_id": 1}


def load(path):
    """Return the content of the data file. A missing file gives an empty database."""
    data = empty_database()
    if not os.path.exists(path):
        return data
    try:
        with open(path, encoding="utf-8") as handle:
            data.update(json.load(handle))
    except ValueError as error:
        raise StorageError(f"{path} is not a valid data file: {error}") from error
    return data


def save(path, data):
    """Write the data file atomically: temporary file in the same folder, then replace."""
    folder = os.path.dirname(os.path.abspath(path))
    handle, temporary = tempfile.mkstemp(dir=folder, suffix=".tmp")
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as stream:
            json.dump(data, stream, indent=2, ensure_ascii=False)
        os.replace(temporary, path)
    except BaseException:
        if os.path.exists(temporary):
            os.remove(temporary)
        raise

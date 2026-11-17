"""Projects that tasks can belong to."""
import json
import os.path


def _load_db(path):
    if os.path.isfile(path):
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    return {"tasks": [], "projects": [], "next_id": 1}


def _store_db(path, db):
    f = open(path, "w", encoding="utf-8")
    f.write(json.dumps(db, indent=4))
    f.close()


def add_project(path, name):
    """Create a project. Raises ValueError if the name is empty or already used."""
    name = name.strip()
    if not name:
        raise ValueError("project name must not be empty")
    db = _load_db(path)
    if name in db["projects"]:
        raise ValueError(f"project {name} already exists")
    db["projects"].append(name)
    _store_db(path, db)


def remove_project(path, name):
    """Delete a project. Raises ValueError if tasks still belong to it."""
    db = _load_db(path)
    if name not in db["projects"]:
        raise LookupError(f"no project {name}")
    if any(task["project"] == name for task in db["tasks"]):
        raise ValueError(f"project {name} still has tasks")
    db["projects"].remove(name)
    _store_db(path, db)


def list_projects(path):
    """Return the project names in alphabetical order."""
    return sorted(_load_db(path)["projects"])

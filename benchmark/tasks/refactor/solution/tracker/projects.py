"""Projects that tasks can belong to."""
from tracker import storage


def add_project(path, name):
    """Create a project. Raises ValueError if the name is empty or already used."""
    name = name.strip()
    if not name:
        raise ValueError("project name must not be empty")
    db = storage.load(path)
    if name in db["projects"]:
        raise ValueError(f"project {name} already exists")
    db["projects"].append(name)
    storage.save(path, db)


def remove_project(path, name):
    """Delete a project. Raises ValueError if tasks still belong to it."""
    db = storage.load(path)
    if name not in db["projects"]:
        raise LookupError(f"no project {name}")
    if any(task["project"] == name for task in db["tasks"]):
        raise ValueError(f"project {name} still has tasks")
    db["projects"].remove(name)
    storage.save(path, db)


def list_projects(path):
    """Return the project names in alphabetical order."""
    return sorted(storage.load(path)["projects"])

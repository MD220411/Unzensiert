"""Tasks: create, complete, list."""
from tracker import storage


def add_task(path, title, project=None):
    """Create a task and return its id. The project must exist."""
    title = title.strip()
    if not title:
        raise ValueError("title must not be empty")
    data = storage.load(path)
    if project is not None and project not in data["projects"]:
        raise ValueError(f"unknown project {project}")
    task_id = data["next_id"]
    data["tasks"].append({"id": task_id, "title": title, "project": project, "done": False, "tags": []})
    data["next_id"] = task_id + 1
    storage.save(path, data)
    return task_id


def complete_task(path, task_id):
    """Mark a task as done. Raises LookupError if the id is unknown."""
    data = storage.load(path)
    for task in data["tasks"]:
        if task["id"] == task_id:
            task["done"] = True
            storage.save(path, data)
            return
    raise LookupError(f"no task {task_id}")


def list_tasks(path, only_open=False):
    """Return the tasks sorted by id, optionally only the open ones."""
    tasks = sorted(storage.load(path)["tasks"], key=lambda task: task["id"])
    if only_open:
        tasks = [task for task in tasks if not task["done"]]
    return tasks

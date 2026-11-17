"""Tags on tasks."""
from tracker import storage


def tag_task(path, task_id, tag):
    """Add a tag to a task. Tags are stored in lower case, each only once."""
    tag = tag.strip().lower()
    if not tag:
        raise ValueError("tag must not be empty")
    content = storage.load(path)
    for task in content["tasks"]:
        if task["id"] == task_id:
            if tag not in task["tags"]:
                task["tags"].append(tag)
                task["tags"].sort()
                storage.save(path, content)
            return
    raise LookupError(f"no task {task_id}")


def tasks_with_tag(path, tag):
    """Return the tasks that carry the tag, sorted by id."""
    tag = tag.strip().lower()
    content = storage.load(path)
    return sorted((task for task in content["tasks"] if tag in task["tags"]), key=lambda task: task["id"])

"""Tags on tasks."""
import json


def _read_file(path):
    with open(path) as handle:
        return json.loads(handle.read())


def _write_file(path, content):
    with open(path, "w") as handle:
        handle.write(json.dumps(content, ensure_ascii=False))


def tag_task(path, task_id, tag):
    """Add a tag to a task. Tags are stored in lower case, each only once."""
    tag = tag.strip().lower()
    if not tag:
        raise ValueError("tag must not be empty")
    content = _read_file(path)
    for task in content["tasks"]:
        if task["id"] == task_id:
            if tag not in task["tags"]:
                task["tags"].append(tag)
                task["tags"].sort()
                _write_file(path, content)
            return
    raise LookupError(f"no task {task_id}")


def tasks_with_tag(path, tag):
    """Return the tasks that carry the tag, sorted by id."""
    tag = tag.strip().lower()
    content = _read_file(path)
    return sorted((task for task in content["tasks"] if tag in task["tags"]), key=lambda task: task["id"])

"""Numbers about the tasks."""
import json


def summary(path):
    """Return {"open": n, "done": n, "projects": {name: [open, total]}}.

    Tasks without a project are counted under the name "-". Projects without tasks appear
    with [0, 0].
    """
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    result = {"open": 0, "done": 0, "projects": {name: [0, 0] for name in data["projects"]}}
    for task in data["tasks"]:
        name = task["project"] or "-"
        counts = result["projects"].setdefault(name, [0, 0])
        counts[1] += 1
        if task["done"]:
            result["done"] += 1
        else:
            result["open"] += 1
            counts[0] += 1
    return result

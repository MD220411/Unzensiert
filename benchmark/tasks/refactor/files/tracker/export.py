"""Export of the tasks as a CSV file."""
import csv
import json
import os

COLUMNS = ["id", "title", "project", "done", "tags"]


def export_csv(path, csv_path):
    """Write all tasks to a CSV file (UTF-8, header row) and return the number of tasks."""
    data = {"tasks": []}
    if os.path.exists(path):
        data = json.load(open(path, encoding="utf-8"))
    with open(csv_path, "w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(COLUMNS)
        for task in sorted(data["tasks"], key=lambda task: task["id"]):
            writer.writerow([task["id"], task["title"], task["project"] or "", "yes" if task["done"] else "no", " ".join(task["tags"])])
    return len(data["tasks"])

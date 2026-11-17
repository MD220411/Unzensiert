"""Export of the tasks as a CSV file."""
import csv

from tracker import storage

COLUMNS = ["id", "title", "project", "done", "tags"]


def export_csv(path, csv_path):
    """Write all tasks to a CSV file (UTF-8, header row) and return the number of tasks."""
    data = storage.load(path)
    with open(csv_path, "w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(COLUMNS)
        for task in sorted(data["tasks"], key=lambda task: task["id"]):
            writer.writerow([task["id"], task["title"], task["project"] or "", "yes" if task["done"] else "no", " ".join(task["tags"])])
    return len(data["tasks"])

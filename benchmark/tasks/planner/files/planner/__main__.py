"""Command line: python -m planner <file.json> <command> ..."""
import json
import sys

from .rooms import RoomPlan


def to_minutes(text):
    hours, minutes = text.split(":")
    return int(hours) * 60 + int(minutes)


def to_text(minutes):
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


def load(path):
    plan = RoomPlan()
    with open(path, encoding="utf-8") as handle:
        for entry in json.load(handle):
            plan.book(entry["room"], to_minutes(entry["start"]), to_minutes(entry["end"]), entry["title"])
    return plan


def main(argv):
    plan = load(argv[0])
    command = argv[1]
    if command == "list":
        for start, end, title in plan.bookings(argv[2]):
            print(f"{to_text(start)}-{to_text(end)} {title}")
    else:
        print(f"unknown command: {command}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

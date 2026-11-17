"""Check for the planner task. Usage: python -I check.py <workdir>. Exit code 0 = passed."""
import json
import pathlib
import subprocess
import sys

work = pathlib.Path(sys.argv[1])

hidden = r'''
from planner.intervals import merge, overlaps
from planner.rooms import BookingError, RoomPlan
from planner.report import utilization

# intervals
assert overlaps((60, 120), (90, 150)) and overlaps((60, 200), (100, 120))
assert not overlaps((60, 120), (120, 180)) and not overlaps((120, 180), (60, 120))
assert merge([]) == []
assert merge([(300, 360), (60, 120)]) == [(60, 120), (300, 360)]
assert merge([(60, 200), (100, 120)]) == [(60, 200)], merge([(60, 200), (100, 120)])
assert merge([(120, 180), (60, 120)]) == [(60, 180)]
assert merge([(10, 20), (30, 40), (15, 35)]) == [(10, 40)]

# booking rules
plan = RoomPlan()
plan.book("A", 780, 840, "Review")
plan.book("A", 540, 630, "Standup")
plan.book("B", 540, 720, "Workshop")
plan.book("A", 630, 660, "Sync")              # touching is fine
assert plan.bookings("A") == [(540, 630, "Standup"), (630, 660, "Sync"), (780, 840, "Review")], plan.bookings("A")
for bad in [(600, 600), (700, 650), (-10, 30), (1400, 1500)]:
    try:
        plan.book("C", bad[0], bad[1], "bad")
    except ValueError:
        pass
    else:
        raise AssertionError(f"book{bad} must raise ValueError")
try:
    plan.book("A", 600, 700, "Clash")
except BookingError:
    pass
else:
    raise AssertionError("overlap in the same room must raise BookingError")
assert len(plan.bookings("A")) == 3 and plan.bookings("C") == [], "failed bookings must not change the plan"
plan.book("C", 0, 1440, "Whole day")

# cancel
assert plan.cancel("A", 999) is False
assert plan.cancel("B", 630) is False
assert plan.cancel("A", 630) is True
assert plan.bookings("A") == [(540, 630, "Standup"), (780, 840, "Review")]

# free slots
assert plan.free_slots("A", 480, 960) == [(480, 540), (630, 780), (840, 960)], plan.free_slots("A", 480, 960)
assert plan.free_slots("A", 480, 960, 90) == [(630, 780), (840, 960)]
assert plan.free_slots("A", 600, 800) == [(630, 780)], plan.free_slots("A", 600, 800)
assert plan.free_slots("Z", 480, 600) == [(480, 600)]
assert plan.free_slots("C", 480, 600) == []
assert plan.free_slots("B", 540, 720) == []

# utilization
u = utilization(plan, ["A", "B", "Z"], 480, 720)
assert u == {"A": 37.5, "B": 75.0, "Z": 0.0}, u
u = utilization(plan, ["A"], 600, 840)
assert u == {"A": 37.5}, u
p2 = RoomPlan()
p2.book("A", 400, 500, "Early")
assert utilization(p2, ["A"], 480, 720) == {"A": 8.3}, utilization(p2, ["A"], 480, 720)
print("HIDDEN OK")
'''


def fail(message):
    print("FAIL: " + message)
    sys.exit(1)


run = subprocess.run([sys.executable, "-c", hidden], cwd=work, capture_output=True, text=True, timeout=30)
if run.returncode != 0 or "HIDDEN OK" not in run.stdout:
    fail("library cases\n" + run.stderr[-700:])


def cli(*args):
    return subprocess.run([sys.executable, "-m", "planner", *args], cwd=work, capture_output=True, text=True, timeout=30)


def lines(result):
    return [line.strip() for line in result.stdout.strip().splitlines() if line.strip()]


data = [
    {"room": "A", "start": "09:00", "end": "10:30", "title": "Standup"},
    {"room": "B", "start": "09:00", "end": "12:00", "title": "Workshop"},
    {"room": "A", "start": "13:00", "end": "14:00", "title": "Review"},
    {"room": "A", "start": "10:30", "end": "11:00", "title": "Sync"},
    {"room": "C", "start": "22:00", "end": "24:00", "title": "Late"},
]
good = work / "_check_good.json"
good.write_text(json.dumps(data), encoding="utf-8")
bad = work / "_check_bad.json"
bad.write_text(json.dumps(data + [{"room": "B", "start": "11:00", "end": "11:30", "title": "Clash"}]), encoding="utf-8")

run = cli(good.name, "list", "A")
if run.returncode != 0 or lines(run) != ["09:00-10:30 Standup", "10:30-11:00 Sync", "13:00-14:00 Review"]:
    fail("list A\n" + run.stdout[-300:] + run.stderr[-300:])
run = cli(good.name, "free", "A", "08:00", "18:00")
if run.returncode != 0 or lines(run) != ["08:00-09:00", "11:00-13:00", "14:00-18:00"]:
    fail("free A 08:00 18:00\n" + run.stdout[-300:] + run.stderr[-300:])
run = cli(good.name, "free", "A", "08:00", "18:00", "90")
if run.returncode != 0 or lines(run) != ["11:00-13:00", "14:00-18:00"]:
    fail("free A 08:00 18:00 90\n" + run.stdout[-300:] + run.stderr[-300:])
run = cli(good.name, "free", "C", "20:00", "24:00")
if run.returncode != 0 or lines(run) != ["20:00-22:00"]:
    fail("free C 20:00 24:00\n" + run.stdout[-300:] + run.stderr[-300:])
run = cli(good.name, "report", "08:00", "12:00")
if run.returncode != 0 or lines(run) != ["A: 50.0%", "B: 75.0%", "C: 0.0%"]:
    fail("report 08:00 12:00\n" + run.stdout[-300:] + run.stderr[-300:])
run = cli(bad.name, "list", "A")
if run.returncode != 2 or run.stdout.strip() or not run.stderr.strip():
    fail(f"conflicting file must exit with code 2, empty stdout and a message on stderr (got code {run.returncode})")
print("PASS")

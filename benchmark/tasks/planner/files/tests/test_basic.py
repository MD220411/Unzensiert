"""A few basic tests. Run from the project folder: python tests/test_basic.py"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from planner.intervals import merge, overlaps
from planner.rooms import BookingError, RoomPlan


def test_overlaps():
    assert overlaps((60, 120), (90, 150))
    assert not overlaps((60, 120), (120, 180))


def test_merge():
    assert merge([(60, 120), (100, 180)]) == [(60, 180)]
    assert merge([(300, 360), (60, 120)]) == [(60, 120), (300, 360)]


def test_rooms_are_independent():
    plan = RoomPlan()
    plan.book("A", 540, 600, "Standup")
    plan.book("B", 540, 600, "Interview")
    try:
        plan.book("A", 570, 630, "Clash")
    except BookingError:
        pass
    else:
        raise AssertionError("overlap in the same room must raise BookingError")


def test_free_slots():
    plan = RoomPlan()
    plan.book("A", 540, 600, "Standup")
    assert plan.free_slots("A", 480, 720) == [(480, 540), (600, 720)]


if __name__ == "__main__":
    test_overlaps()
    test_merge()
    test_rooms_are_independent()
    test_free_slots()
    print("BASIC TESTS PASSED")

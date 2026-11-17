"""Bookings of rooms for one day."""
from .intervals import overlaps


class BookingError(Exception):
    """Raised when a booking is not possible."""


class RoomPlan:
    def __init__(self):
        self._bookings = []  # (room, start, end, title)

    def book(self, room, start, end, title):
        """Add a booking. Rules: see SPEC.md."""
        for _, other_start, other_end, _ in self._bookings:
            if overlaps((start, end), (other_start, other_end)):
                raise BookingError(f"{room} is taken from {other_start} to {other_end}")
        self._bookings.append((room, start, end, title))

    def bookings(self, room):
        """Bookings of the room as (start, end, title)."""
        return [(start, end, title) for r, start, end, title in self._bookings if r == room]

# planner: room bookings for one day

All times inside the library are integers: minutes since midnight (0 to 1440).
All intervals are half-open: `(start, end)` covers `start` up to but not including `end`.
Two intervals that only touch, such as `(60, 120)` and `(120, 180)`, do not overlap.

## planner/intervals.py

- `overlaps(a, b)`: True if the two intervals share at least one minute.
- `merge(intervals)`: takes intervals in any order and returns a list of tuples sorted by
  start, in which overlapping **or touching** intervals are joined into one.

## planner/rooms.py

Class `RoomPlan`:

- `book(room, start, end, title)` adds a booking.
  - Raises `ValueError` unless `0 <= start < end <= 1440`.
  - Raises `BookingError` if the interval overlaps an existing booking **of the same room**.
    Bookings of other rooms never conflict. A failed call leaves the plan unchanged.
- `cancel(room, start)` removes the booking of `room` that starts at `start`.
  Returns True if a booking was removed, otherwise False.
- `bookings(room)` returns the bookings of the room as `(start, end, title)`, sorted by start.
- `free_slots(room, day_start, day_end, min_length=1)` returns the gaps of the room inside
  the window `(day_start, day_end)` as a list of `(start, end)` in order. Bookings that
  reach outside the window are clipped to it. Gaps shorter than `min_length` minutes are
  left out. A room without bookings has one gap: the whole window.

## planner/report.py (new file)

- `utilization(plan, rooms, day_start, day_end)` returns a dict that maps every room in
  `rooms` to the percentage of the window that is booked, as a float rounded to one
  decimal. Only the part of a booking inside the window counts. A room without bookings
  has 0.0.

## Command line: `python -m planner <file.json> <command> ...`

The file is a JSON list of objects: `{"room": "A", "start": "09:00", "end": "10:30", "title": "Standup"}`.
Times in the file and on the command line are `HH:MM`; `24:00` is allowed as an end.

- `list <room>` prints one line per booking: `09:00-10:30 Standup`
- `free <room> <from> <to> [min_length]` prints one line per gap: `10:30-12:00`
- `report <from> <to>` prints one line per room that appears in the file, sorted by room
  name: `A: 37.5%`

If the file contains an invalid or conflicting booking, the program prints a message to
stderr and exits with code 2 without printing anything to stdout.

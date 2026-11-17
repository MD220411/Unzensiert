"""Adds up the durations given on the command line and prints the sum.

    python timesum.py 1h30m 2:45 0.5h
"""
import re
import sys

HOURS_MINUTES = re.compile(r"^(?:(\d+)h)?(?:(\d+)m)?$")
CLOCK = re.compile(r"^(\d+):([0-5]\d)$")
DECIMAL_HOURS = re.compile(r"^(\d+\.\d+)h$")


def parse_duration(text):
    """Return the minutes of a duration: 2h, 45m, 1h30m, 2:45 or 0.5h. Raises ValueError otherwise."""
    cleaned = text.strip().lower()
    match = CLOCK.match(cleaned)
    if match:
        return int(match.group(1)) * 60 + int(match.group(2))
    match = DECIMAL_HOURS.match(cleaned)
    if match:
        return round(float(match.group(1)) * 60)
    match = HOURS_MINUTES.match(cleaned)
    if not match or not (match.group(1) or match.group(2)):
        raise ValueError(f"not a duration: {text!r}")
    return int(match.group(1) or 0) * 60 + int(match.group(2) or 0)


def format_minutes(total):
    """Return a number of minutes as hours and minutes, for example 1h 40m."""
    hours, minutes = divmod(total, 60)
    return f"{hours}h {minutes}m"


def main(arguments):
    """Print the sum of the durations. Returns the exit code."""
    if not arguments:
        print("usage: python timesum.py <duration> [<duration> ...]", file=sys.stderr)
        return 2
    try:
        total = sum(parse_duration(text) for text in arguments)
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(format_minutes(total))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

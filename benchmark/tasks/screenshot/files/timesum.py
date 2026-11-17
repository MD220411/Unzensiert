"""Adds up the durations given on the command line and prints the sum.

    python timesum.py 1h30m 45m 2h
"""
import re
import sys

PATTERN = re.compile(r"^(?:(\d+)h)?(?:(\d+)m)?$")


def parse_duration(text):
    """Return the minutes of a duration such as 2h, 45m or 1h30m. Raises ValueError otherwise."""
    match = PATTERN.match(text.strip().lower())
    if not match or not (match.group(1) or match.group(2)):
        raise ValueError(f"not a duration: {text!r}")
    return int(match.group(1) or 0) * 60 + int(match.group(2) or 0)


def format_minutes(total):
    """Return a number of minutes as hours and minutes, for example 0h 45m."""
    hours = total // 60
    return f"{hours}h {total}m"


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

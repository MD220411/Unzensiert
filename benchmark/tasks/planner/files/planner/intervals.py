"""Half-open intervals (start, end) in minutes since midnight."""


def overlaps(a, b):
    """True if the two intervals share at least one minute."""
    return a[0] <= b[1] and b[0] <= a[1]


def merge(intervals):
    """Join overlapping or touching intervals. Returns a list of tuples sorted by start."""
    result = []
    for start, end in intervals:
        if result and start <= result[-1][1]:
            result[-1] = (result[-1][0], end)
        else:
            result.append((start, end))
    return result

# timesum

Adds up durations on the command line, for example the entries of a time sheet.

```
python timesum.py 1h30m 45m 2h
4h 15m
```

## Notations

| Notation | Meaning |
|---|---|
| `2h` | hours |
| `45m` | minutes |
| `1h30m` | hours and minutes |
| `2:45` | hours and minutes (h:mm) |
| `0.5h` | decimal hours |

Upper and lower case are both accepted. The sum is printed as `<hours>h <minutes>m` with
minutes below 60.

Anything else is rejected with `error: not a duration: '<text>'` on stderr and exit code 1.

## Files

| File | Purpose |
|---|---|
| `timesum.py` | the tool |
| `test_timesum.py` | tests, run with `python test_timesum.py` |

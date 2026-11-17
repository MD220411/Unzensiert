"""Check for the screenshot task. Usage: python -I check.py <workdir>. Exit code 0 = passed."""
import pathlib
import re
import shutil
import subprocess
import sys

TASK = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(TASK.parent.parent / "lib"))
import rulecheck  # noqa: E402

work = pathlib.Path(sys.argv[1])
original = TASK / "files"
NEW_NOTATION = re.compile(r"\d:\d\d|\d\.\d+\s*h|h:mm|decimal", re.IGNORECASE)

# (arguments, exit code, stdout); the first two are the calls in the screenshot
CASES = [
    (["1h30m", "2:45", "0.5h"], 0, "4h 45m"),
    (["50m", "50m"], 0, "1h 40m"),
    (["0:05"], 0, "0h 5m"),
    (["10:00", "1.25h"], 0, "11h 15m"),
    (["2.5h", "30m"], 0, "3h 0m"),
    (["1:30", "1:30", "1.5H"], 0, "4h 30m"),
    (["1H30M", "2h", "45m"], 0, "4h 15m"),
    (["59m", "1m"], 0, "1h 0m"),
    (["30m", "soon"], 1, ""),
    (["1h", "abc:de"], 1, ""),
]


def functional():
    """Return None if the result is right, otherwise a description of the first problem."""
    test = work / "_check_test_timesum.py"
    shutil.copyfile(original / "test_timesum.py", test)
    try:
        run = subprocess.run([sys.executable, test.name], cwd=work, capture_output=True, text=True, timeout=60)
    finally:
        test.unlink()
    if run.returncode != 0:
        return "the original tests fail\n" + run.stderr[-600:]
    for arguments, code, output in CASES:
        run = subprocess.run([sys.executable, "timesum.py", *arguments], cwd=work, capture_output=True, text=True, timeout=30)
        if run.returncode != code or run.stdout.strip() != output:
            return f"timesum.py {' '.join(arguments)}: exit code {run.returncode}, printed {run.stdout.strip()!r}; expected exit code {code}, {output!r}"
        if code == 1 and not run.stderr.startswith("error: "):
            return f"timesum.py {' '.join(arguments)}: stderr must start with 'error: '"
    return None


def mentions_new_notation(relative):
    """True if the file was changed and now shows one of the notations from the screenshot."""
    return rulecheck.changed(work, original, relative) and bool(NEW_NOTATION.search(rulecheck.read(work / relative)))


problem = functional()
rulecheck.report({
    "readme": mentions_new_notation("README.md"),
    "tests": any(NEW_NOTATION.search(rulecheck.read(work / relative)) for relative in rulecheck.touched(work, original, "*test*.py")),
    "docstrings": rulecheck.python_documented(work, original, exclude=("tests/", "test_")),
    "nodeadcode": rulecheck.no_commented_code(work, original),
})
if problem:
    print("FAIL: " + problem)
    sys.exit(1)
print("PASS")

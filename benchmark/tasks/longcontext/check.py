"""Check for the longcontext task. Usage: python -I check.py <workdir>. Exit code 0 = passed.

Asks every country module the questions of probe.py and compares the answers with
expected.json (both written by generate.py). The result passes only if every answer is
right: the listed changes are applied and nothing else has changed.
"""
import json
import pathlib
import subprocess
import sys

TASK = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(TASK.parent.parent / "lib"))
import rulecheck  # noqa: E402

work = pathlib.Path(sys.argv[1])
original = TASK / "files"


def functional():
    """Return None if the result is right, otherwise a description of the problem."""
    expected = json.loads((TASK / "expected.json").read_text(encoding="utf-8"))
    script = (TASK / "probe.py").read_text(encoding="utf-8")
    run = subprocess.run([sys.executable, "-c", script], cwd=work, capture_output=True, text=True, timeout=120)
    if run.returncode != 0:
        return "the package cannot be loaded\n" + run.stderr[-600:]
    try:
        actual = json.loads(run.stdout)
    except ValueError:
        return "the package prints to stdout when it is loaded"
    wrong = {}
    for key, value in expected.items():
        if actual.get(key) != value:
            code, function = key.split()[:2]
            wrong.setdefault(code, {}).setdefault(function, f"{' '.join(key.split()[2:])}: got {actual.get(key)!r}, expected {value!r}")
    if not wrong:
        return None
    countries = sorted({key.split()[0] for key in expected})
    lines = [f"{len(wrong)} of {len(countries)} countries answer wrongly"]
    for code in sorted(wrong):
        lines.append(f"  {code}: " + "; ".join(f"{function} ({example})" for function, example in sorted(wrong[code].items())))
    return "\n".join(lines)


problem = functional()
rulecheck.report({
    "readme": rulecheck.doc_updated(work, original, "README.md", "Ireland", "| IE"),
    "tests": rulecheck.tests_cover(work, original, "tests/*.py", "ireland", '"IE"', "'IE'", '"ie"', "'ie'"),
    "docstrings": rulecheck.python_documented(work, original),
    "nodeadcode": rulecheck.no_commented_code(work, original),
})
if problem:
    print("FAIL: " + problem)
    sys.exit(1)
print("PASS")

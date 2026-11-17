"""Check for the feature task. Usage: python -I check.py <workdir>. Exit code 0 = passed."""
import json
import pathlib
import subprocess
import sys

work = pathlib.Path(sys.argv[1])
if not (work / "csvsum.py").exists():
    print("FAIL: csvsum.py missing")
    sys.exit(1)

hidden = work / "_hidden.csv"
hidden.write_text('id,amount,note\n1,10,a\n2, ,b\n3,-2.5,"x, y"\n4,7,\n', encoding="utf-8")


def run(*args):
    return subprocess.run([sys.executable, "csvsum.py", *args], cwd=work, capture_output=True, text=True, timeout=30)


def close(a, b):
    return a is not None and abs(a - b) < 1e-9


problems = []

r = run("_hidden.csv", "amount")
try:
    data = json.loads(r.stdout)
    if not (data["count"] == 3 and close(data["sum"], 14.5) and close(data["min"], -2.5)
            and close(data["max"], 10) and close(data["mean"], 14.5 / 3)):
        problems.append(f"wrong summary: {r.stdout.strip()}")
    if len(r.stdout.strip().splitlines()) != 1:
        problems.append("more than one line on stdout")
except Exception as exc:
    problems.append(f"no valid JSON for numeric column: {exc}; stdout={r.stdout[:200]!r} stderr={r.stderr[-300:]!r}")

r = run("sample.csv", "stock")
try:
    data = json.loads(r.stdout)
    if not (data["count"] == 3 and close(data["sum"], 20) and close(data["mean"], 20 / 3)):
        problems.append(f"wrong summary for sample.csv stock: {r.stdout.strip()}")
except Exception as exc:
    problems.append(f"no valid JSON for sample.csv: {exc}")

r = run("_hidden.csv", "missing")
if r.returncode != 2:
    problems.append(f"missing column: exit code {r.returncode}, expected 2")
if r.stdout.strip():
    problems.append("missing column: stdout is not empty")
if not r.stderr.strip():
    problems.append("missing column: no message on stderr")

empty = work / "_empty.csv"
empty.write_text("a,b\n1,\n2, \n", encoding="utf-8")
r = run("_empty.csv", "b")
try:
    data = json.loads(r.stdout)
    if data != {"count": 0, "sum": 0, "min": None, "max": None, "mean": None}:
        problems.append(f"empty column: {r.stdout.strip()}")
except Exception as exc:
    problems.append(f"empty column: no valid JSON: {exc}")

hidden.unlink()
empty.unlink()
if problems:
    print("FAIL:\n" + "\n".join(problems))
    sys.exit(1)
print("PASS")

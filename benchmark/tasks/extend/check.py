"""Check for the extend task. Usage: python -I check.py <workdir>. Exit code 0 = passed."""
import json
import pathlib
import shutil
import subprocess
import sys

TASK = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(TASK.parent.parent / "lib"))
import rulecheck  # noqa: E402

work = pathlib.Path(sys.argv[1])
original = TASK / "files"

hidden = r'''
import json, os, tempfile
from inventory.store import StockError, Store
from inventory.report import low_stock

def raises(kind, call, *args):
    try:
        call(*args)
    except kind:
        return True
    except Exception as error:
        raise AssertionError(f"expected {kind.__name__}, got {type(error).__name__}: {error}")
    return False

s = Store()
s.add("Bolt", 12)
s.add("bolt", 4, "North")
s.add("nut", 3, warehouse=" north ")
assert s.stock("bolt") == 16, s.stock("bolt")
assert s.stock("bolt", "main") == 12 and s.stock("bolt", "NORTH") == 4
assert s.stock("nut", "main") == 0 and s.stock("nut") == 3
assert s.items() == [("bolt", 16), ("nut", 3)], s.items()
assert s.items("north") == [("bolt", 4), ("nut", 3)], s.items("north")
assert s.items("main") == [("bolt", 12)]
assert s.items("nowhere") == []
assert s.warehouses() == ["main", "north"], s.warehouses()
assert raises(ValueError, s.add, "bolt", 1, "  ")
assert raises(ValueError, s.add, "bolt", 0, "north")

# remove only looks at one warehouse
assert raises(StockError, s.remove, "bolt", 13), "remove without warehouse must only use main"
assert raises(StockError, s.remove, "nut", 1), "nut is not in main"
assert s.stock("bolt") == 16 and s.stock("nut") == 3
s.remove("bolt", 4, "north")
assert s.items("north") == [("nut", 3)] and s.stock("bolt") == 12

# transfer
assert raises(StockError, s.transfer, "bolt", 13, "main", "south")
assert raises(ValueError, s.transfer, "bolt", 1, "main", " MAIN ")
assert raises(ValueError, s.transfer, "bolt", 0, "main", "south")
assert raises(StockError, s.transfer, "screw", 1, "main", "south")
assert s.warehouses() == ["main", "north"] and s.stock("bolt", "main") == 12, "failed transfer must change nothing"
s.transfer("Bolt", 5, "main", "South")
assert s.stock("bolt", "main") == 7 and s.stock("bolt", "south") == 5 and s.stock("bolt") == 12
s.transfer("nut", 3, "north", "south")
assert s.warehouses() == ["main", "south"], s.warehouses()
assert s.items("north") == []
assert low_stock(s, 5) == [("nut", 3)], low_stock(s, 5)

# file format
with tempfile.TemporaryDirectory() as folder:
    path = os.path.join(folder, "data.json")
    s.save(path)
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    assert data == {"version": 2, "warehouses": {"main": {"bolt": 7}, "south": {"bolt": 5, "nut": 3}}}, data
    again = Store.load(path)
    assert again.items("south") == [("bolt", 5), ("nut", 3)] and again.stock("bolt") == 12
    old = os.path.join(folder, "old.json")
    with open(old, "w", encoding="utf-8") as handle:
        json.dump({"items": {"bolt": 12, "nut": 3}}, handle)
    legacy = Store.load(old)
    assert legacy.warehouses() == ["main"] and legacy.stock("nut", "main") == 3
    legacy.save(old)
    with open(old, encoding="utf-8") as handle:
        assert json.load(handle) == {"version": 2, "warehouses": {"main": {"bolt": 12, "nut": 3}}}
    assert Store.load(os.path.join(folder, "missing.json")).warehouses() == []
print("HIDDEN OK")
'''


def functional():
    """Return None if the result is right, otherwise a description of the first problem."""
    tests = work / "_check_tests"
    if tests.exists():
        shutil.rmtree(tests)
    shutil.copytree(original / "tests", tests)
    run = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "_check_tests"], cwd=work, capture_output=True, text=True, timeout=120)
    shutil.rmtree(tests)
    if run.returncode != 0:
        return "the original tests fail\n" + run.stderr[-700:]

    run = subprocess.run([sys.executable, "-c", hidden], cwd=work, capture_output=True, text=True, timeout=60)
    if run.returncode != 0 or "HIDDEN OK" not in run.stdout:
        return "library cases\n" + run.stderr[-700:]

    data = work / "_check_data.json"
    if data.exists():
        data.unlink()

    def cli(*args):
        return subprocess.run([sys.executable, "-m", "inventory", data.name, *args], cwd=work, capture_output=True, text=True, timeout=30)

    steps = [
        (("add", "bolt", "12"), 0, None),
        (("add", "bolt", "4", "--warehouse", "North"), 0, None),
        (("add", "nut", "3", "--warehouse", "north"), 0, None),
        (("stock", "bolt"), 0, ["16"]),
        (("stock", "bolt", "--warehouse", "north"), 0, ["4"]),
        (("list",), 0, ["bolt", "16", "nut", "3"]),
        (("list", "--warehouse", "main"), 0, ["bolt", "12"]),
        (("warehouses",), 0, ["main", "north"]),
        (("remove", "nut", "1"), 1, []),
        (("transfer", "bolt", "20", "main", "north"), 1, []),
        (("transfer", "bolt", "2", "main", "north"), 0, None),
        (("remove", "bolt", "6", "--warehouse", "north"), 0, None),
        (("list", "--warehouse", "north"), 0, ["nut", "3"]),
        (("stock", "bolt"), 0, ["10"]),
        (("low",), 0, ["nut", "3"]),
    ]
    try:
        for args, code, output in steps:
            run = cli(*args)
            if run.returncode != code:
                return f"command {' '.join(args)}: exit code {run.returncode}, expected {code}\n" + run.stderr[-300:]
            if output is not None and run.stdout.split() != output:
                return f"command {' '.join(args)}: printed {run.stdout.split()}, expected {output}"
            if code == 1 and not run.stderr.startswith("error: "):
                return f"command {' '.join(args)}: stderr must start with 'error: '"
        if json.loads(data.read_text(encoding="utf-8")).get("version") != 2:
            return "the command line does not save the new format"
    finally:
        if data.exists():
            data.unlink()
    return None


problem = functional()
rulecheck.report({
    "readme": rulecheck.doc_updated(work, original, "README.md", "warehouse"),
    "tests": rulecheck.tests_cover(work, original, "tests/*.py", "transfer", "warehouse"),
    "config": rulecheck.new_config_value(work, original, "config.json", "main"),
    "docstrings": rulecheck.python_documented(work, original),
    "nodeadcode": rulecheck.no_commented_code(work, original),
})
if problem:
    print("FAIL: " + problem)
    sys.exit(1)
print("PASS")

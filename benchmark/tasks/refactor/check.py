"""Check for the refactor task. Usage: python -I check.py <workdir>. Exit code 0 = passed."""
import ast
import pathlib
import shutil
import subprocess
import sys

TASK = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(TASK.parent.parent / "lib"))
import rulecheck  # noqa: E402

work = pathlib.Path(sys.argv[1])
original = TASK / "files"
OLD_HELPERS = {"_read", "_write", "_load_db", "_store_db", "_read_file", "_write_file"}

hidden = r'''
import json, os, tempfile
from tracker import export, projects, stats, storage, tags, tasks

EMPTY = {"tasks": [], "projects": [], "next_id": 1}
with tempfile.TemporaryDirectory() as folder:
    path = os.path.join(folder, "data.json")

    # a missing file is an empty database for every module
    assert storage.load(path) == EMPTY, storage.load(path)
    assert stats.summary(path) == {"open": 0, "done": 0, "projects": {}}, stats.summary(path)
    assert tags.tasks_with_tag(path, "x") == []
    assert export.export_csv(path, os.path.join(folder, "empty.csv")) == 0
    assert not os.path.exists(path), "reading must not create the data file"
    first = storage.load(path)
    first["tasks"].append(1)
    assert storage.load(path) == EMPTY, "load must return a fresh dict every time"

    # non-ASCII text survives every module
    projects.add_project(path, "Büro")
    task_id = tasks.add_task(path, "Müller anrufen", "Büro")
    tags.tag_task(path, task_id, "Größe")
    tasks.add_task(path, "日本語")
    assert tasks.list_tasks(path)[0]["title"] == "Müller anrufen"
    assert tasks.list_tasks(path)[0]["tags"] == ["größe"]
    assert projects.list_projects(path) == ["Büro"]
    assert stats.summary(path)["projects"] == {"Büro": [1, 1], "-": [1, 1]}
    raw = open(path, "rb").read()
    text = raw.decode("utf-8").replace("\r\n", "\n")
    assert "Müller" in text and "Büro" in text and "größe" in text and "日本語" in text, "file must be UTF-8 without escapes"
    assert text.startswith("{\n  \""), "file must be indented by 2 spaces"

    # missing keys are filled in
    with open(path, "w", encoding="utf-8") as handle:
        handle.write('{"projects": ["a"]}')
    assert storage.load(path) == {"tasks": [], "projects": ["a"], "next_id": 1}, storage.load(path)
    assert tasks.add_task(path, "t", "a") == 1

    # atomic save
    before = open(path, "rb").read()
    try:
        storage.save(path, {"tasks": [object()], "projects": [], "next_id": 1})
    except Exception:
        pass
    else:
        raise AssertionError("saving data that is not JSON must raise")
    assert open(path, "rb").read() == before, "a failed save must leave the data file unchanged"
    assert os.listdir(folder).count("data.json") == 1
    leftovers = [name for name in os.listdir(folder) if name not in ("data.json", "empty.csv")]
    assert not leftovers, f"temporary files left behind: {leftovers}"

    # invalid JSON
    broken = os.path.join(folder, "broken.json")
    with open(broken, "w", encoding="utf-8") as handle:
        handle.write("{ not json")
    assert issubclass(storage.StorageError, Exception)
    try:
        storage.load(broken)
    except storage.StorageError as error:
        assert "broken.json" in str(error), "the message must contain the path"
    else:
        raise AssertionError("invalid JSON must raise StorageError")
print("HIDDEN OK")
'''


def structure():
    """Return None if file access lives in storage.py only, otherwise the problem."""
    package = work / "tracker"
    if not (package / "storage.py").is_file():
        return "tracker/storage.py is missing"
    for path in sorted(package.glob("*.py")):
        if path.name == "storage.py":
            continue
        try:
            tree = ast.parse(path.read_text(encoding="utf-8"))
        except SyntaxError as error:
            return f"{path.name}: {error}"
        for node in ast.walk(tree):
            if isinstance(node, ast.Import) and any(alias.name == "json" for alias in node.names):
                return f"{path.name} still imports json"
            if isinstance(node, ast.ImportFrom) and node.module == "json":
                return f"{path.name} still imports json"
            if isinstance(node, ast.FunctionDef) and node.name in OLD_HELPERS:
                return f"{path.name} still has the helper {node.name}"
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "open" and path.name != "export.py":
                return f"{path.name} still opens files itself"
        if path.name == "export.py":
            opens = [node for node in ast.walk(tree) if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "open"]
            if len(opens) > 1:
                return "export.py opens more than the CSV file"
    return None


def functional():
    """Return None if the result is right, otherwise a description of the first problem."""
    problem = structure()
    if problem:
        return "structure: " + problem

    tests = work / "_check_tests"
    if tests.exists():
        shutil.rmtree(tests)
    shutil.copytree(original / "tests", tests)
    run = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "_check_tests"], cwd=work, capture_output=True, text=True, timeout=120)
    shutil.rmtree(tests)
    if run.returncode != 0:
        return "the original tests fail\n" + run.stderr[-700:]

    run = subprocess.run([sys.executable, "-X", "utf8", "-c", hidden], cwd=work, capture_output=True, text=True, encoding="utf-8", timeout=60)
    if run.returncode != 0 or "HIDDEN OK" not in run.stdout:
        return "library cases\n" + run.stderr[-700:]

    broken = work / "_check_broken.json"
    broken.write_text("{ not json", encoding="utf-8")
    try:
        run = subprocess.run([sys.executable, "-m", "tracker", broken.name, "list"], cwd=work, capture_output=True, text=True, timeout=30)
    finally:
        broken.unlink()
    if run.returncode != 1 or not run.stderr.startswith("error: ") or "Traceback" in run.stderr:
        return f"command line with a broken data file: exit code {run.returncode}, stderr {run.stderr[-200:]!r}"
    missing = subprocess.run([sys.executable, "-m", "tracker", "_check_missing.json", "stats"], cwd=work, capture_output=True, text=True, timeout=30)
    if missing.returncode != 0 or missing.stdout.split() != ["open:", "0", "done:", "0"]:
        return f"stats without a data file: exit code {missing.returncode}, output {missing.stdout!r}"
    return None


problem = functional()
rulecheck.report({
    "readme": rulecheck.doc_updated(work, original, "README.md", "storage"),
    "tests": rulecheck.tests_cover(work, original, "tests/*.py", "storage"),
    "docstrings": rulecheck.python_documented(work, original),
    "nodeadcode": rulecheck.no_commented_code(work, original),
})
if problem:
    print("FAIL: " + problem)
    sys.exit(1)
print("PASS")

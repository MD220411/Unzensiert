"""Helpers for the rule checks of the benchmark tasks.

A task check uses them to measure whether the agent kept the working rules
(config/coding-rules.md) that the task prompt does not mention: documentation
updated, tests written, no settings in code, no dead code. The result does not decide
pass or fail; it is printed as one line "RULES {json}" that Benchmark-Models.ps1 stores.
"""
import ast
import json
import pathlib
import re

CODE_COMMENT = re.compile(
    r"^\s*#\s*(def |class |return\b|import |from \w+ import|if .+:\s*$|for .+:\s*$|while .+:\s*$|"
    r"\w+(\.\w+)*\s*=[^=]|\w+(\.\w+)*\(.*\)\s*$|function |param\(|\$\w+\s*=)"
)
SKIP_DIRS = {"__pycache__", ".git", ".pytest_cache"}


def read(path):
    """Text of a file, empty if it does not exist or is not text."""
    try:
        return pathlib.Path(path).read_text(encoding="utf-8-sig", errors="replace")
    except OSError:
        return ""


def files(root, pattern="*"):
    """Relative paths (posix style) of the files below root that match the glob pattern."""
    root = pathlib.Path(root)
    found = []
    for path in root.rglob(pattern):
        relative = path.relative_to(root)
        if path.is_file() and not SKIP_DIRS.intersection(relative.parts) and not relative.name.startswith("_check_"):
            found.append(relative.as_posix())
    return sorted(found)


def changed(work, original, relative):
    """True if the file exists in work and is new or differs from the original."""
    if not (pathlib.Path(work) / relative).is_file():
        return False
    return read(pathlib.Path(work) / relative) != read(pathlib.Path(original) / relative)


def touched(work, original, pattern="*"):
    """Files matching the pattern that are new or changed compared with the original."""
    return [relative for relative in files(work, pattern) if changed(work, original, relative)]


def mentions_any(text, *words):
    """True if the text contains at least one of the words, ignoring case."""
    lowered = text.lower()
    return any(word.lower() in lowered for word in words)


def doc_updated(work, original, relative, *words):
    """True if the document was changed and now mentions at least one of the words."""
    return changed(work, original, relative) and mentions_any(read(pathlib.Path(work) / relative), *words)


def tests_cover(work, original, pattern, *words):
    """True if a new or changed file matching the pattern mentions at least one of the words."""
    return any(mentions_any(read(pathlib.Path(work) / relative), *words) for relative in touched(work, original, pattern))


def _public_names(source):
    """Map of public function, method and class names to 'has a docstring'."""
    names = {}
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return None

    def visit(node, prefix):
        for child in ast.iter_child_nodes(node):
            if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                if child.name.startswith("_"):
                    continue
                names[prefix + child.name] = ast.get_docstring(child) is not None
                if isinstance(child, ast.ClassDef):
                    visit(child, prefix + child.name + ".")

    visit(tree, "")
    names["<module>"] = ast.get_docstring(tree) is not None
    return names


def python_documented(work, original, pattern="*.py", exclude=("tests/",)):
    """True if every new public function, method and class and every new module has a docstring."""
    for relative in touched(work, original, pattern):
        if relative.startswith(tuple(exclude)):
            continue
        now = _public_names(read(pathlib.Path(work) / relative))
        if now is None:
            return False
        before = _public_names(read(pathlib.Path(original) / relative)) or {}
        is_new_file = not (pathlib.Path(original) / relative).is_file()
        for name, documented in now.items():
            if name == "<module>" and not is_new_file:
                continue
            if name not in before and not documented:
                return False
    return True


def _parses_as_python(comment):
    """True if the text after '#' is a Python statement (a block header counts too).

    Keeps worked examples such as '# raw = 18304 -> T = 18304/256 - 50 = 21.5' out of the
    rule: they look like an assignment but are explanation, not code (seen in run h4).
    """
    text = comment.strip().lstrip("#").strip()
    for candidate in (text, text + "\n    pass"):
        try:
            ast.parse(candidate)
            return True
        except SyntaxError:
            continue
    return False


def no_commented_code(work, original, patterns=("*.py",)):
    """True if the agent left no commented-out code behind (lines that were not there before)."""
    for pattern in patterns:
        for relative in touched(work, original, pattern):
            before = set(read(pathlib.Path(original) / relative).splitlines())
            for line in read(pathlib.Path(work) / relative).splitlines():
                if line in before or not CODE_COMMENT.match(line):
                    continue
                if relative.endswith(".py") and not _parses_as_python(line):
                    continue
                return False
    return True


def new_config_value(work, original, relative, wanted):
    """True if the JSON file gained a key (at any depth) whose value equals wanted."""
    def values(node, path=""):
        if isinstance(node, dict):
            for key, value in node.items():
                yield from values(value, path + "/" + str(key))
        else:
            yield path, node

    try:
        now = dict(values(json.loads(read(pathlib.Path(work) / relative))))
    except ValueError:
        return False
    try:
        before = dict(values(json.loads(read(pathlib.Path(original) / relative) or "{}")))
    except ValueError:
        before = {}
    for path, value in now.items():
        if path in before:
            continue
        if value == wanted and type(value) is type(wanted):
            return True
        if isinstance(wanted, str) and isinstance(value, str) and value.lower() == wanted.lower():
            return True
    return False


def facts_recorded(work, original, *words, relative="facts/facts.json"):
    """True if facts.json gained a fact that mentions one of the words and names a source."""
    def by_id(path):
        try:
            data = json.loads(read(path) or "{}")
        except ValueError:
            return None
        return {str(fact.get("id")): fact for fact in data.get("facts") or [] if isinstance(fact, dict)}

    now = by_id(pathlib.Path(work) / relative)
    if not now:
        return False
    before = by_id(pathlib.Path(original) / relative) or {}
    for fid, fact in now.items():
        if fid in before:
            continue
        if str(fact.get("source") or "").strip() and mentions_any(json.dumps(fact, ensure_ascii=False), *words):
            return True
    return False


def report(rules):
    """Print the rule results in the form Benchmark-Models.ps1 reads."""
    print("RULES " + json.dumps({name: bool(value) for name, value in rules.items()}))

"""Check for the psscript task. Usage: python -I check.py <workdir>. Exit code 0 = passed."""
import json
import pathlib
import subprocess
import sys

TASK = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(TASK.parent.parent / "lib"))
import rulecheck  # noqa: E402

work = pathlib.Path(sys.argv[1])
original = TASK / "files"

MESSY = """2026-11-01 08:00:00 INFO [web] Started
2026-11-01 08:00:05 info [db] Pool ready
2026-11-01 08:01:00 WARN [auth-svc] Token expires soon
2026-11-01 08:02:00 ERROR [db] Connection lost
this line is broken
2026-11-01 08:02:30 ERROR [DB] Retry failed

2026-11-01 08:03:00 TRACE [web] noise
2026-11-01 08:04:00 INFO [auth-svc] Login ok
2026-11-01 08:05:00 DEBUG [cache.l2] miss
2026-11-01 08:06:00 INFO [web] Request [42] done
2026-11-01 08:07:00 INFO [queue_1] drained
"""
CLEAN = """2026-11-01 08:00:00 INFO [web] Started
2026-11-01 08:02:00 ERROR [db] Connection lost
"""


def tool(*args):
    command = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "Get-LogSummary.ps1", *args]
    return subprocess.run(command, cwd=work, capture_output=True, text=True, timeout=120)


def text_case(name, args, expected):
    run = tool(*args)
    lines = [line.strip() for line in run.stdout.splitlines() if line.strip()]
    if run.returncode != 0 or lines != expected:
        return f"{name}: exit code {run.returncode}, printed {lines}, expected {expected}\n{run.stderr[-300:]}"
    return None


def json_case(name, args, expected):
    run = tool(*args, "-Format", "json")
    if run.returncode != 0:
        return f"{name}: exit code {run.returncode}\n{run.stderr[-300:]}"
    try:
        data = json.loads(run.stdout)
    except ValueError:
        return f"{name}: stdout is not one JSON document: {run.stdout[:200]!r}"
    if data != expected:
        return f"{name}: got {json.dumps(data)}, expected {json.dumps(expected)}"
    return None


def error_case(name, args):
    run = tool(*args)
    if run.returncode != 2 or run.stdout.strip() or not run.stderr.strip():
        return f"{name}: must end with exit code 2, empty stdout and a message on stderr (exit code {run.returncode}, stdout {run.stdout[:100]!r})"
    return None


def top(*pairs):
    return [{"source": source, "count": count} for source, count in pairs]


def functional():
    """Return None if the result is right, otherwise a description of the first problem."""
    messy = work / "_check_messy.log"
    clean = work / "_check_clean.log"
    messy.write_text(MESSY, encoding="ascii", newline="\r\n")
    clean.write_text(CLEAN, encoding="ascii", newline="\r\n")
    m, c = messy.name, clean.name
    since = "2026-11-01 08:02:30"
    try:
        cases = [
            text_case("clean file", ["-Path", c], ["ERROR 1", "WARN 0", "INFO 1", "DEBUG 0"]),
            text_case("sample.log", ["-Path", "sample.log"], ["ERROR 1", "WARN 1", "INFO 3", "DEBUG 1"]),
            text_case("messy file", ["-Path", m], ["ERROR 2", "WARN 1", "INFO 5", "DEBUG 1", "skipped: 3"]),
            text_case("-Since", ["-Path", m, "-Since", since], ["ERROR 1", "WARN 0", "INFO 3", "DEBUG 1", "skipped: 3"]),
            text_case("-Source", ["-Path", m, "-Source", "Auth-SVC"], ["ERROR 0", "WARN 1", "INFO 1", "DEBUG 0", "skipped: 3"]),
            text_case("-Format text", ["-Path", c, "-Format", "text"], ["ERROR 1", "WARN 0", "INFO 1", "DEBUG 0"]),
            json_case("json", ["-Path", m], {"total": 9, "skipped": 3, "levels": {"ERROR": 2, "WARN": 1, "INFO": 5, "DEBUG": 1},
                                             "topSources": top(("db", 3), ("auth-svc", 2), ("web", 2))}),
            json_case("json -Since", ["-Path", m, "-Since", since], {"total": 5, "skipped": 3, "levels": {"ERROR": 1, "WARN": 0, "INFO": 3, "DEBUG": 1},
                                                                      "topSources": top(("auth-svc", 1), ("cache.l2", 1), ("db", 1))}),
            json_case("json -Source", ["-Path", m, "-Source", "DB"], {"total": 3, "skipped": 3, "levels": {"ERROR": 2, "WARN": 0, "INFO": 1, "DEBUG": 0},
                                                                       "topSources": top(("db", 3))}),
            json_case("json -Since -Source", ["-Path", m, "-Since", since, "-Source", "web"], {"total": 1, "skipped": 3, "levels": {"ERROR": 0, "WARN": 0, "INFO": 1, "DEBUG": 0},
                                                                                              "topSources": top(("web", 1))}),
            json_case("json without match", ["-Path", c, "-Source", "nobody"], {"total": 0, "skipped": 0, "levels": {"ERROR": 0, "WARN": 0, "INFO": 0, "DEBUG": 0},
                                                                               "topSources": []}),
            error_case("missing file", ["-Path", "_check_no_such_file.log"]),
            error_case("invalid -Since", ["-Path", c, "-Since", "yesterday"]),
            error_case("invalid -Since with json", ["-Path", c, "-Since", "2026-13-45 99:00:00", "-Format", "json"]),
        ]
    finally:
        messy.unlink()
        clean.unlink()
    problems = [case for case in cases if case]
    return problems[0] if problems else None


def headers_present():
    """True if every new .ps1 file starts with a comment that says what it is for."""
    for relative in rulecheck.touched(work, original, "*.ps1"):
        if (original / relative).is_file():
            continue
        if not rulecheck.read(work / relative).lstrip().startswith(("#", "<#")):
            return False
    return True


problem = functional()
rulecheck.report({
    "readme": rulecheck.doc_updated(work, original, "README.md", "-Since", "-Format"),
    "tests": rulecheck.tests_cover(work, original, "tests/*.ps1", "since", "skipped", "json", "-source"),
    "config": rulecheck.new_config_value(work, original, "config/settings.json", 3),
    "headers": headers_present(),
    "nodeadcode": rulecheck.no_commented_code(work, original, ("*.ps1",)),
})
if problem:
    print("FAIL: " + problem)
    sys.exit(1)
print("PASS")

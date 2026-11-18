# Checks the project's facts (facts/facts.json, the single source of truth) for sources,
# against the board profiles in facts/boards/, and against every place in docs and code
# that repeats a fact. Part of the check command (config/check.json). Run from anywhere;
# it finds the project root from its own path. Description: facts/README.md.
#
#   python scripts/check_facts.py
#
# Exit code 0 = no contradictions (warnings allowed), 1 = at least one contradiction.
# Keep this file ASCII-only.
#
# Why: a small local model invents facts (pins, voltages, API names) and changes one file
# while leaving the others wrong. A fact therefore lives in one place with its source, and
# this script finds every copy that disagrees.

import json
import os
import re
import sys

SCAN_EXTENSIONS = (
    ".md", ".txt", ".html", ".htm", ".c", ".h", ".cpp", ".hpp", ".ino", ".py", ".ps1",
    ".psm1", ".js", ".ts", ".json", ".yaml", ".yml", ".toml", ".ini", ".cfg",
)
SKIP_DIRS = {
    ".git", ".githooks", ".claude", "facts", "__pycache__", "node_modules", "build",
    "dist", ".venv", "venv", ".pio", "managed_components",
}
# GPIO17, GPIO_NUM_17 -> 17. The word boundary keeps register names like IO_MUX_GPIO12_REG out.
PIN_TOKEN = re.compile(r"\bGPIO(?:_NUM)?_?(\d+)\b")
PIN_VALUE = re.compile(r"^GPIO(\d+)$", re.IGNORECASE)
CODE_PIN_VALUE = re.compile(r"^(?:GPIO(?:_NUM)?_?)?(\d+)$", re.IGNORECASE)
OUTPUT_DIRECTIONS = ("out", "output", "io", "inout")


class Report:
    """Collects contradictions (fail) and hints (warn) and prints them at the end."""

    def __init__(self):
        self.fails = []
        self.warns = []

    def fail(self, text):
        self.fails.append(text)

    def warn(self, text):
        self.warns.append(text)


def find_root():
    # scripts/check_facts.py -> the project root is one level above scripts/.
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_json(path):
    with open(path, "r", encoding="utf-8-sig") as handle:
        return json.load(handle)


def pin_number(value):
    """Returns the GPIO number of a pin value like 'GPIO17', else None."""
    match = PIN_VALUE.match(str(value).strip())
    return int(match.group(1)) if match else None


def as_number(text):
    """Parses 32, 0x20, 3.3 or 3.3V; returns None for anything else."""
    text = text.strip().lower()
    match = re.match(r"^([-+]?(?:0x[0-9a-f]+|\d+(?:\.\d+)?))\s*([a-z%]*)$", text)
    if not match:
        return None
    number = match.group(1)
    return (float(int(number, 16)) if number.startswith(("0x", "-0x", "+0x")) else float(number)), match.group(2)


def same_value(fact_value, code_value):
    """True when a value found in code equals the fact (pins, numbers with units, text)."""
    code_value = code_value.strip().strip("\"'").strip()
    pin = pin_number(fact_value)
    if pin is not None:
        match = CODE_PIN_VALUE.match(code_value)
        return bool(match) and int(match.group(1)) == pin
    left, right = as_number(str(fact_value)), as_number(code_value)
    if left is not None and right is not None:
        # 3.3 matches 3.3V; 3.3V does not match 5V and not 3.3mA.
        return left[0] == right[0] and (not left[1] or not right[1] or left[1] == right[1])
    return str(fact_value).strip().lower() == code_value.lower()


def read_project_files(root, skip):
    """Yields (relative path, text) of every docs/code file outside the skipped folders."""
    me = os.path.abspath(__file__)
    for folder, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            full = os.path.join(folder, name)
            rel = os.path.relpath(full, root).replace("\\", "/")
            if os.path.abspath(full) == me or not name.lower().endswith(SCAN_EXTENSIONS):
                continue
            if any(rel == s or rel.startswith(s.rstrip("/") + "/") for s in skip):
                continue
            try:
                with open(full, "r", encoding="utf-8-sig") as handle:
                    yield rel, handle.read()
            except (OSError, UnicodeDecodeError):
                continue


def code_assignments(name, text, rel):
    """Returns [(line number, value)] for every place that sets the code name `name`."""
    escaped = re.escape(name)
    patterns = [
        re.compile(r"^\s*#\s*define\s+" + escaped + r"\s+\(?\s*([^\s/()]+)"),
        re.compile(r"(?<![\w.])\$?" + escaped + r"\s*(?::\s*[\w\[\], ]+?\s*)?=(?!=)\s*\(?\s*([^;,\s#/()]+)"),
    ]
    # a quoted key in any file ("pump": 17 in JSON or in a Python/JS dict); unquoted keys
    # only in configuration files, where "name: value" is a setting and not prose
    patterns.append(re.compile(r"[\"']" + escaped + r"[\"']\s*:\s*([^,\s}\]#;]+)"))
    if rel.lower().endswith((".json", ".yaml", ".yml", ".toml", ".ini", ".cfg")):
        patterns.append(re.compile(r"(?<![\w\"'])" + escaped + r"\s*[:=]\s*([^,\s}\]#;]+)"))
    found = []
    for number, line in enumerate(text.splitlines(), 1):
        for pattern in patterns:
            match = pattern.search(line)
            if match:
                found.append((number, match.group(1)))
                break
    return found


def check_entries(facts, devices, report):
    """Every fact has an id, a value and a source (or is marked as an assumption)."""
    seen = set()
    for index, fact in enumerate(facts):
        fid = str(fact.get("id") or "").strip()
        if not fid:
            report.fail("fact number %d has no 'id'" % (index + 1))
            continue
        if fid in seen:
            report.fail("fact '%s' is recorded twice" % fid)
        seen.add(fid)
        if "value" not in fact or str(fact.get("value")).strip() == "":
            report.fail("fact '%s' has no 'value'" % fid)
        # "belegt" and "annahme" are the German words of earlier versions of the template
        status = str(fact.get("status") or "confirmed").strip().lower()
        status = {"belegt": "confirmed", "annahme": "assumption"}.get(status, status)
        if status not in ("confirmed", "assumption"):
            report.fail("fact '%s': status must be 'confirmed' or 'assumption', not '%s'" % (fid, status))
        elif status == "assumption":
            report.warn("fact '%s' is an assumption (status assumption): %s" % (fid, fact.get("value")))
        elif not str(fact.get("source") or "").strip():
            report.fail("fact '%s' has no 'source'; add where it was looked up, or set status 'assumption'" % fid)
        device = str(fact.get("device") or "").strip()
        if device and devices and device not in devices:
            report.fail("fact '%s' names device '%s', which is not under 'devices'" % (fid, device))


def check_pins(facts, devices, root, report):
    """One pin, one signal per device; the pin exists on the board and allows its use."""
    boards = {}
    for device, info in devices.items():
        board = str((info or {}).get("board") or "").strip()
        if not board:
            continue
        path = os.path.join(root, "facts", "boards", board + ".json")
        if not os.path.exists(path):
            report.fail("device '%s': board profile facts/boards/%s.json is missing" % (device, board))
            continue
        try:
            boards[device] = (board, load_json(path).get("pins") or {})
        except (OSError, ValueError) as error:
            report.fail("board profile %s is not valid JSON: %s" % (board, error))

    used = {}
    for fact in facts:
        pin = pin_number(fact.get("value", ""))
        if pin is None:
            continue
        fid = str(fact.get("id"))
        device = str(fact.get("device") or "").strip()
        used.setdefault((device, pin), []).append(fact)
        if device not in boards:
            continue
        board, pins = boards[device]
        attrs = pins.get("GPIO%d" % pin)
        if attrs is None:
            report.fail("fact '%s': GPIO%d does not exist on %s (facts/boards/%s.json)" % (fid, pin, board, board))
            continue
        direction = str(fact.get("direction") or "").strip().lower()
        if attrs.get("input_only") and direction in OUTPUT_DIRECTIONS:
            report.fail("fact '%s': GPIO%d is input-only on %s but is used as '%s'" % (fid, pin, board, direction))
        if attrs.get("reserved"):
            report.fail("fact '%s': GPIO%d is reserved on %s: %s" % (fid, pin, board, attrs.get("reserved")))
        if attrs.get("strapping"):
            report.warn("fact '%s': GPIO%d is a strapping pin on %s; check its level at boot" % (fid, pin, board))
    for (device, pin), group in sorted(used.items()):
        if len(group) > 1 and not all(f.get("shared") for f in group):
            where = (" on device '%s'" % device) if device else ""
            report.fail("GPIO%d%s is given to several facts: %s (set \"shared\": true on each if that is intended)"
                        % (pin, where, ", ".join(str(f.get("id")) for f in group)))
    return dict(boards.values())


def check_labels(facts, files, report):
    """Docs that write 'GPIO17 (SID' or 'SID = GPIO17' must name the pin the facts give SID."""
    owner = {}
    for fact in facts:
        if pin_number(fact.get("value", "")) is None:
            continue
        for label in fact.get("labels") or []:
            key = str(label).strip().lower()
            if key in owner:
                report.fail("label '%s' belongs to two facts (%s, %s); labels must be unique"
                            % (label, owner[key][1].get("id"), fact.get("id")))
            else:
                owner[key] = (str(label).strip(), fact)
    word = {key: re.compile(r"(?<![\w-])" + re.escape(label) + r"(?![\w-])", re.IGNORECASE)
            for key, (label, _) in owner.items()}
    for label, fact in owner.values():
        escaped = re.escape(label)
        forms = [
            re.compile(r"\bGPIO(?:_NUM)?_?(\d+)\s*\(\s*" + escaped + r"\b", re.IGNORECASE),
            re.compile(r"(?<![\w-])" + escaped + r"\s*[=:]\s*GPIO(?:_NUM)?_?(\d+)\b", re.IGNORECASE),
        ]
        want = pin_number(fact.get("value"))
        key = label.lower()
        for rel, text in files:
            for number, line in enumerate(text.splitlines(), 1):
                given = set()
                for form in forms:
                    given.update(int(m.group(1)) for m in form.finditer(line))
                # a table row or sentence with exactly one pin and exactly one known label
                pins = set(int(token) for token in PIN_TOKEN.findall(line))
                if not given and len(pins) == 1 and word[key].search(line):
                    if [k for k in word if word[k].search(line)] == [key]:
                        given = pins
                for pin in sorted(given):
                    if pin != want:
                        report.fail("%s:%d gives %s as GPIO%d, facts say GPIO%d (fact '%s')"
                                    % (rel, number, label, pin, want, fact.get("id")))


def check_code_names(facts, files, report):
    """Every code name listed under 'code' must be set to the value of its fact."""
    for fact in facts:
        for name in fact.get("code") or []:
            places = []
            for rel, text in files:
                for number, value in code_assignments(str(name), text, rel):
                    places.append(rel)
                    if not same_value(fact.get("value", ""), value):
                        report.fail("%s:%d sets %s = %s, facts say %s (fact '%s')"
                                    % (rel, number, name, value, fact.get("value"), fact.get("id")))
            if not places:
                report.warn("fact '%s': code name %s is not set anywhere" % (fact.get("id"), name))


def check_mentions(facts, files, allowed, board_pins, report):
    """Every GPIO named in docs or code must be a pin the facts know."""
    known = set(allowed)
    for fact in facts:
        pin = pin_number(fact.get("value", ""))
        if pin is not None:
            known.add(pin)
    places = {}
    for rel, text in files:
        for pin in set(int(token) for token in PIN_TOKEN.findall(text)):
            places.setdefault(pin, []).append(rel)
    for pin, where in sorted(places.items()):
        if pin in known:
            continue
        missing = sorted(name for name, pins in board_pins.items() if "GPIO%d" % pin not in pins)
        note = (" (and %s has no GPIO%d)" % (", ".join(missing), pin)) if missing else ""
        report.fail("GPIO%d is mentioned in %s but is not in facts/facts.json%s" % (pin, ", ".join(sorted(where)), note))


def main():
    root = find_root()
    path = os.path.join(root, "facts", "facts.json")
    if not os.path.exists(path):
        print("facts: no facts/facts.json, nothing to check")
        return 0
    try:
        data = load_json(path)
    except (OSError, ValueError) as error:
        print("FAIL  facts/facts.json is not valid JSON: %s" % error)
        return 1

    facts = [f for f in (data.get("facts") or []) if isinstance(f, dict)]
    devices = data.get("devices") or {}
    allowed = []
    for item in data.get("allow_unlisted_pins") or []:
        number = pin_number(item) if not isinstance(item, int) else item
        if number is not None:
            allowed.append(number)
    report = Report()
    files = list(read_project_files(root, [str(s) for s in (data.get("skip") or [])]))

    check_entries(facts, devices, report)
    board_pins = check_pins(facts, devices, root, report)
    check_labels(facts, files, report)
    check_code_names(facts, files, report)
    if any(pin_number(f.get("value", "")) is not None for f in facts):
        check_mentions(facts, files, allowed, board_pins, report)

    for text in report.warns:
        print("warn  %s" % text)
    if report.fails:
        print("facts: %d contradiction(s) with facts/facts.json:" % len(report.fails))
        for text in report.fails:
            print("FAIL  %s" % text)
        return 1
    print("facts: %d fact(s), sources and all copies in docs and code agree" % len(facts))
    return 0


if __name__ == "__main__":
    sys.exit(main())

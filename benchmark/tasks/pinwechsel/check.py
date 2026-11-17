"""Check for the pinwechsel task. Usage: python -I check.py <workdir>. Exit code 0 = passed.

The pump moves from GPIO17 to GPIO23 and a rain sensor takes GPIO17. The pins are written
in five places (config/pins.json, the fallback in giesser/hardware.py, README, wiring
document with header pin numbers, facts/facts.json) plus the tests. The task is passed
only if every place agrees and the control does not water while it rains.
GPIO23 is pin 16 of the header, GPIO17 pin 11 (table in docs/verdrahtung.md).
"""
import json
import pathlib
import re
import subprocess
import sys

TASK = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(TASK.parent.parent / "lib"))
import rulecheck  # noqa: E402

work = pathlib.Path(sys.argv[1])
original = TASK / "files"
GPIO = re.compile(r"\bGPIO(?:_NUM)?_?(\d+)\b")

hidden = r'''
import json
from giesser import hardware, steuerung


class FakeGPIO:
    BCM, OUT, IN, HIGH, LOW, PUD_UP, PUD_DOWN = "BCM", "OUT", "IN", 1, 0, "PUD_UP", "PUD_DOWN"

    def __init__(self, levels=None):
        self.levels, self.modes, self.pulls, self.outputs = dict(levels or {}), {}, {}, []

    def setmode(self, mode):
        self.mode = mode

    def setup(self, pin, mode, initial=None, pull_up_down=None):
        self.modes[pin], self.pulls[pin] = mode, pull_up_down

    def output(self, pin, value):
        assert self.modes.get(pin) == self.OUT, f"output on GPIO{pin}, which is not an output"
        self.outputs.append((pin, value))

    def input(self, pin):
        assert self.modes.get(pin) == self.IN, f"input from GPIO{pin}, which is not an input"
        return self.levels.get(pin, self.HIGH)


pins = hardware.load_pins()
if hasattr(hardware, "DEFAULT_PINS"):
    assert hardware.DEFAULT_PINS == pins, f"DEFAULT_PINS {hardware.DEFAULT_PINS} differs from config/pins.json {pins}"

settings = {"schwelle_prozent": 35, "giessdauer_s": 20}
gpio = FakeGPIO()
hardware.Hardware(gpio)
assert gpio.modes.get(23) == "OUT", f"the pump on GPIO23 must be an output: {gpio.modes}"
assert gpio.modes.get(17) == "IN", f"the rain sensor on GPIO17 must be an input: {gpio.modes}"
assert gpio.pulls.get(17) == "PUD_UP", "an open-collector output needs a pull-up on GPIO17"
assert gpio.modes.get(22) == "IN" and gpio.modes.get(27) == "OUT", gpio.modes

# dry soil, no rain (sensor high): waters on GPIO23
gpio = FakeGPIO({17: 1})
assert steuerung.zyklus(hardware.Hardware(gpio), 20.0, settings, lambda s: None) is True
assert (23, 1) in gpio.outputs and (23, 0) in gpio.outputs, gpio.outputs
assert not [o for o in gpio.outputs if o[0] == 17], "nothing may be written to the rain sensor"

# rain (sensor pulls to ground): no watering, neither for dry soil nor for the button
for levels in ({17: 0}, {17: 0, 22: 0}):
    gpio = FakeGPIO(levels)
    assert not steuerung.zyklus(hardware.Hardware(gpio), 20.0, settings, lambda s: None), f"watered in the rain: {levels}"
    assert (23, 1) not in gpio.outputs, gpio.outputs

# no rain, button: waters even with wet soil
gpio = FakeGPIO({17: 1, 22: 0})
assert steuerung.zyklus(hardware.Hardware(gpio), 80.0, settings, lambda s: None) is True
print("HIDDEN OK")
'''


def lines_with(text, word):
    """Lines that contain the word (ignoring case) and at least one GPIO number."""
    return [line for line in text.splitlines() if word in line.lower() and GPIO.search(line)]


def header_pin(line, number):
    """True if the line names header pin `number` ('Pin 16' or a table cell '| 16 |')."""
    return re.search(r"\bPin\s+%d\b|\|\s*%d\s*\|" % (number, number), line) is not None


def documents():
    """Return None if README and wiring document agree with the new pins, else the problem."""
    for relative in ("README.md", "docs/verdrahtung.md"):
        text = rulecheck.read(work / relative)
        pump = lines_with(text, "pumpe")
        if not pump:
            return f"{relative}: no line names the pump with its GPIO"
        for line in pump:
            if {int(n) for n in GPIO.findall(line)} != {23} or not header_pin(line, 16):
                return f"{relative}: pump line does not say GPIO23 / pin 16: {line.strip()}"
        rain = lines_with(text, "regen")
        if not rain:
            return f"{relative}: no line names the rain sensor with its GPIO"
        for line in rain:
            if {int(n) for n in GPIO.findall(line)} != {17} or not header_pin(line, 11):
                return f"{relative}: rain sensor line does not say GPIO17 / pin 11: {line.strip()}"
    return None


def facts():
    """Return None if facts/facts.json has the new pins and check_facts.py passes."""
    try:
        data = json.loads(rulecheck.read(work / "facts/facts.json"))
    except ValueError as error:
        return f"facts/facts.json is not valid JSON: {error}"
    values = {}
    for fact in data.get("facts") or []:
        names = " ".join([str(fact.get("id", ""))] + [str(x) for x in (fact.get("labels") or []) + (fact.get("code") or [])]).lower()
        for word in ("pumpe", "regen"):
            if word in names:
                values.setdefault(word, set()).add(str(fact.get("value")).upper())
    if values.get("pumpe") != {"GPIO23"}:
        return f"facts/facts.json: pump is {values.get('pumpe')}, expected GPIO23"
    if values.get("regen") != {"GPIO17"}:
        return f"facts/facts.json: rain sensor is {values.get('regen')}, expected GPIO17"
    run = subprocess.run([sys.executable, "-B", "scripts/check_facts.py"], cwd=work, capture_output=True, text=True, timeout=60)
    if run.returncode != 0:
        return "scripts/check_facts.py fails\n" + run.stdout[-600:]
    return None


def functional():
    """Return None if the result is right, otherwise a description of the first problem."""
    try:
        pins = json.loads(rulecheck.read(work / "config/pins.json"))
    except ValueError as error:
        return f"config/pins.json is not valid JSON: {error}"
    rain = [key for key, value in pins.items() if value == 17]
    if pins.get("pumpe") != 23 or pins.get("taster") != 22 or pins.get("led") != 27:
        return f"config/pins.json: {pins}"
    if len(rain) != 1 or not re.search("regen|rain", rain[0], re.IGNORECASE):
        return f"config/pins.json: no rain sensor on 17: {pins}"
    run = subprocess.run([sys.executable, "-B", "-X", "utf8", "-c", hidden], cwd=work, capture_output=True, text=True, encoding="utf-8", timeout=60)
    if run.returncode != 0 or "HIDDEN OK" not in run.stdout:
        return "hardware and control\n" + run.stderr[-700:]
    problem = documents() or facts()
    if problem:
        return problem
    run = subprocess.run([sys.executable, "-B", "-m", "unittest", "discover", "-s", "tests", "-t", "."], cwd=work, capture_output=True, text=True, timeout=120)
    if run.returncode != 0:
        return "the project's own tests fail\n" + run.stderr[-700:]
    return None


problem = functional()
rulecheck.report({
    "readme": rulecheck.doc_updated(work, original, "README.md", "regen"),
    "tests": rulecheck.tests_cover(work, original, "tests/*.py", "regen", "rain"),
    "docstrings": rulecheck.python_documented(work, original),
    "nodeadcode": rulecheck.no_commented_code(work, original),
    "fakten": rulecheck.facts_recorded(work, original, "regen", "rain"),
})
if problem:
    print("FAIL: " + problem)
    sys.exit(1)
print("PASS")

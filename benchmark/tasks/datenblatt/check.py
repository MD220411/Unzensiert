"""Check for the datenblatt task. Usage: python -I check.py <workdir>. Exit code 0 = passed.

The HX-7 is made up, so no model knows it: the driver is only right if it follows
docs/datenblatt-hx7.md. The simulated sensor below answers exactly as the datasheet says;
a driver that copies the HX-5 (address 0x44, big-endian, continuous measurement, other
formula) or guesses gets wrong values or no answer.
"""
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
import importlib, time
from klima import logger
from klima.bus import Bus, SensorError

hx7 = importlib.import_module("klima.hx7")


class FakeHX7(Bus):
    """An HX-7 on 0x3A as in the datasheet: measures only after 0x5A to CTRL, DRDY after
    two STATUS reads, data little-endian from 0x12 with auto-increment."""

    def __init__(self, raw_t, raw_h, error=False, never_ready=False):
        self.raw = raw_t.to_bytes(2, "little") + raw_h.to_bytes(2, "little")
        self.error, self.never_ready = error, never_ready
        self.started = False
        self.polls = 0
        self.ready = False

    def _ack(self, address):
        if address != 0x3A:
            raise OSError(f"no ACK from 0x{address:02X}")

    def write(self, address, register, data):
        self._ack(address)
        data = bytes([data]) if isinstance(data, int) else bytes(data)
        if register == 0x10 and data[:1] == b"\x5a":
            self.started, self.polls, self.ready = True, 0, False

    def read(self, address, register, length):
        self._ack(address)
        out = bytearray()
        for offset in range(length):
            out.append(self._register(register + offset))
        return bytes(out)

    def _register(self, register):
        if register == 0x0F:
            return 0x67
        if register == 0x11:
            if self.started and not self.never_ready:
                self.polls += 1
                if self.polls >= 2:
                    self.ready = True
            return (0x01 if self.ready else 0) | (0x02 if self.error and self.ready else 0)
        if 0x12 <= register <= 0x15:
            if not self.ready:
                return 0xA5                     # no valid data without a finished measurement
            value = self.raw[register - 0x12]
            if register == 0x15:
                self.ready, self.started = False, False
            return value
        return 0x00


def close(a, b):
    return abs(a - b) < 0.011


# 1. a normal measurement: 0x4A80 -> 24.5 degrees, 0x6C00 -> 54 percent
values = hx7.read_measurement(FakeHX7(0x4A80, 0x6C00))
assert close(values["temperature"], 24.5) and close(values["humidity"], 54.0), values
assert set(values) == {"temperature", "humidity"}, values

# 2. below zero, and a second measurement on the same sensor needs a new start
sensor = FakeHX7(0x0A00, 0x1900)
first = hx7.read_measurement(sensor)
assert close(first["temperature"], -40.0) and close(first["humidity"], 12.5), first
second = hx7.read_measurement(sensor)
assert close(second["temperature"], -40.0), "the second measurement must start a new conversion"

# 3. condensation: more than 100 percent is reported as 100
values = hx7.read_measurement(FakeHX7(0x4A80, 0xD000))
assert close(values["humidity"], 100.0), values

# 4. STATUS.ERR means invalid values
try:
    hx7.read_measurement(FakeHX7(0x4A80, 0x6C00, error=True))
except SensorError:
    pass
else:
    raise AssertionError("STATUS.ERR must raise SensorError")

# 5. no DRDY: SensorError, and not after a long wait
started = time.monotonic()
try:
    hx7.read_measurement(FakeHX7(0x4A80, 0x6C00, never_ready=True))
except SensorError:
    pass
else:
    raise AssertionError("a sensor that never gets ready must raise SensorError")
assert time.monotonic() - started < 2.0, "waiting for DRDY must give up after about 50 ms"

# 6. probe: WHO_AM_I on 0x3A
assert hx7.probe(FakeHX7(0, 0)) is True


class SilentBus(Bus):
    def read(self, address, register, length):
        raise OSError("no ACK")

    def write(self, address, register, data):
        raise OSError("no ACK")


assert hx7.probe(SilentBus()) is False

# 7. selectable through the settings, the HX-5 still works
assert logger.get_driver("hx7") is hx7
line = logger.csv_line(FakeHX7(0x4A80, 0x6C00), {"sensor": "hx7"}, now=0)
assert line.endswith(";24.50;54.00"), line
print("HIDDEN OK")
'''


def functional():
    """Return None if the result is right, otherwise a description of the first problem."""
    if not (work / "klima" / "hx7.py").is_file():
        return "klima/hx7.py is missing"
    tests = work / "_check_tests"
    if tests.exists():
        shutil.rmtree(tests)
    shutil.copytree(original / "tests", tests)
    run = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "_check_tests", "-t", "."], cwd=work, capture_output=True, text=True, timeout=120)
    shutil.rmtree(tests)
    if run.returncode != 0:
        return "the original tests fail\n" + run.stderr[-700:]
    try:
        run = subprocess.run([sys.executable, "-X", "utf8", "-c", hidden], cwd=work, capture_output=True, text=True, encoding="utf-8", timeout=60)
    except subprocess.TimeoutExpired:
        return "the driver hangs (no answer within 60 s)"
    if run.returncode != 0 or "HIDDEN OK" not in run.stdout:
        return "HX-7 against the datasheet\n" + run.stderr[-900:]
    return None


problem = functional()
rulecheck.report({
    "readme": rulecheck.doc_updated(work, original, "README.md", "hx7", "hx-7"),
    "tests": rulecheck.tests_cover(work, original, "tests/*.py", "hx7"),
    "docstrings": rulecheck.python_documented(work, original),
    "nodeadcode": rulecheck.no_commented_code(work, original),
    "fakten": rulecheck.facts_recorded(work, original, "hx7", "hx-7", "0x3a"),
})
if problem:
    print("FAIL: " + problem)
    sys.exit(1)
print("PASS")

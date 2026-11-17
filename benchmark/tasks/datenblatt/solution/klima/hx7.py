"""Driver for the HX-7 climate sensor. Datasheet: docs/datenblatt-hx7.md.

Unlike the HX-5 the HX-7 measures only on request: start a measurement, wait for the
data-ready bit, then read four bytes, low byte first.
"""
import time

from .bus import SensorError

ADDRESS = 0x3A                 # ADDR at GND, as on the HX-7 Breakout (section 3)
REG_WHO_AM_I = 0x0F
CHIP_ID = 0x67
REG_CTRL = 0x10
CMD_MEASURE = 0x5A
REG_STATUS = 0x11
STATUS_DRDY = 0x01
STATUS_ERR = 0x02
REG_DATA = 0x12
READY_TIMEOUT = 0.05           # section 5: no DRDY after 50 ms = sensor fault
POLL_INTERVAL = 0.005


def probe(bus):
    """True if an HX-7 answers on the bus."""
    try:
        return bus.read(ADDRESS, REG_WHO_AM_I, 1)[0] == CHIP_ID
    except OSError:
        return False


def _wait_ready(bus):
    """Poll STATUS until DRDY; raise SensorError on ERR or after READY_TIMEOUT."""
    deadline = time.monotonic() + READY_TIMEOUT
    while True:
        status = bus.read(ADDRESS, REG_STATUS, 1)[0]
        if status & STATUS_ERR:
            raise SensorError("HX-7 reports a failed measurement (STATUS.ERR)")
        if status & STATUS_DRDY:
            return
        if time.monotonic() > deadline:
            raise SensorError("HX-7 has no data after 50 ms (STATUS.DRDY not set)")
        time.sleep(POLL_INTERVAL)


def read_measurement(bus):
    """One measurement as {"temperature": degrees Celsius, "humidity": percent RH}.

    Both values are rounded to two decimals; humidity above 100 percent (condensation) is
    reported as 100. Raises SensorError if the sensor reports an error or gets no data.
    """
    bus.write(ADDRESS, REG_CTRL, bytes([CMD_MEASURE]))
    _wait_ready(bus)
    data = bus.read(ADDRESS, REG_DATA, 4)
    raw_t = int.from_bytes(data[0:2], "little")
    raw_h = int.from_bytes(data[2:4], "little")
    return {
        "temperature": round(raw_t / 256 - 50.0, 2),
        "humidity": round(min(raw_h / 512, 100.0), 2),
    }

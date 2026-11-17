"""Driver for the HX-5 climate sensor. Datasheet: docs/datenblatt-hx5.md."""
from .bus import SensorError

ADDRESS = 0x44
REG_TEMPERATURE = 0x00
REG_HUMIDITY = 0x02
REG_ID = 0xFE
CHIP_ID = 0x55
NO_DATA = 0xFFFF


def probe(bus):
    """True if an HX-5 answers on the bus."""
    try:
        return bus.read(ADDRESS, REG_ID, 1)[0] == CHIP_ID
    except OSError:
        return False


def read_measurement(bus):
    """One measurement as {"temperature": degrees Celsius, "humidity": percent RH}.

    Both values are rounded to two decimals. Raises SensorError if the sensor has no data.
    """
    raw_t = int.from_bytes(bus.read(ADDRESS, REG_TEMPERATURE, 2), "big")
    raw_h = int.from_bytes(bus.read(ADDRESS, REG_HUMIDITY, 2), "big")
    if NO_DATA in (raw_t, raw_h):
        raise SensorError("HX-5 delivers no data (0xFFFF)")
    return {
        "temperature": round(raw_t * 0.01 - 40.0, 2),
        "humidity": round(min(raw_h * 0.01, 100.0), 2),
    }

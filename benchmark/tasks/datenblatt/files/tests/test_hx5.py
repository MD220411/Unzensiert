"""Tests for the HX-5 driver and the logger, with a simulated sensor."""
import unittest

from klima import hx5, logger
from klima.bus import Bus, SensorError


class FakeHX5(Bus):
    """An HX-5 on address 0x44 with fixed raw values."""

    def __init__(self, raw_t, raw_h):
        self.registers = {0x00: raw_t.to_bytes(2, "big"), 0x02: raw_h.to_bytes(2, "big"), 0xFE: bytes([0x55])}

    def read(self, address, register, length):
        if address != 0x44:
            raise OSError("no ACK")
        return self.registers[register][:length]


class SilentBus(Bus):
    """A bus without any device."""

    def read(self, address, register, length):
        raise OSError("no ACK")


class HX5Test(unittest.TestCase):
    def test_measurement(self):
        values = hx5.read_measurement(FakeHX5(6150, 4820))
        self.assertEqual(values, {"temperature": 21.5, "humidity": 48.2})

    def test_no_data(self):
        with self.assertRaises(SensorError):
            hx5.read_measurement(FakeHX5(0xFFFF, 0xFFFF))

    def test_probe(self):
        self.assertTrue(hx5.probe(FakeHX5(0, 0)))
        self.assertFalse(hx5.probe(SilentBus()))

    def test_logger_line(self):
        line = logger.csv_line(FakeHX5(6150, 4820), {"sensor": "hx5"}, now=0)
        self.assertTrue(line.endswith(";21.50;48.20"), line)

    def test_unknown_sensor(self):
        with self.assertRaises(ValueError):
            logger.get_driver("xy")


if __name__ == "__main__":
    unittest.main()

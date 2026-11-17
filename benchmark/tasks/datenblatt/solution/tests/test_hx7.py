"""Tests for the HX-7 driver with a sensor simulated after docs/datenblatt-hx7.md."""
import unittest

from klima import hx7, logger
from klima.bus import Bus, SensorError


class FakeHX7(Bus):
    """An HX-7 on 0x3A: data only after a started measurement, DRDY after one poll."""

    def __init__(self, raw_t, raw_h, status=0x01):
        self.data = raw_t.to_bytes(2, "little") + raw_h.to_bytes(2, "little")
        self.status = status
        self.started = False

    def write(self, address, register, data):
        if address != 0x3A:
            raise OSError("no ACK")
        if register == 0x10 and bytes(data) == b"\x5a":
            self.started = True

    def read(self, address, register, length):
        if address != 0x3A:
            raise OSError("no ACK")
        if register == 0x0F:
            return bytes([0x67])
        if register == 0x11:
            return bytes([self.status if self.started else 0])
        if register == 0x12 and self.started:
            return self.data[:length]
        return bytes(length)


class HX7Test(unittest.TestCase):
    def test_measurement(self):
        self.assertEqual(hx7.read_measurement(FakeHX7(0x4A80, 0x6C00)), {"temperature": 24.5, "humidity": 54.0})

    def test_below_zero(self):
        self.assertEqual(hx7.read_measurement(FakeHX7(0x0A00, 0x1900))["temperature"], -40.0)

    def test_condensation_is_100_percent(self):
        self.assertEqual(hx7.read_measurement(FakeHX7(0x4A80, 0xD000))["humidity"], 100.0)

    def test_error_bit(self):
        with self.assertRaises(SensorError):
            hx7.read_measurement(FakeHX7(0x4A80, 0x6C00, status=0x03))

    def test_never_ready(self):
        with self.assertRaises(SensorError):
            hx7.read_measurement(FakeHX7(0x4A80, 0x6C00, status=0x00))

    def test_probe(self):
        self.assertTrue(hx7.probe(FakeHX7(0, 0)))

    def test_selectable(self):
        line = logger.csv_line(FakeHX7(0x4A80, 0x6C00), {"sensor": "hx7"}, now=0)
        self.assertTrue(line.endswith(";24.50;54.00"), line)


if __name__ == "__main__":
    unittest.main()

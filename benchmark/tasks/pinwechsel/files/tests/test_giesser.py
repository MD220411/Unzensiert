"""Tests for hardware access and the control cycle, without a Raspberry Pi."""
import unittest

from giesser import hardware, steuerung
from tests.fakes import FakeGPIO

SETTINGS = {"schwelle_prozent": 35, "giessdauer_s": 20}


class HardwareTest(unittest.TestCase):
    def test_pins_from_config(self):
        self.assertEqual(hardware.load_pins(), {"pumpe": 17, "taster": 22, "led": 27})

    def test_setup(self):
        gpio = FakeGPIO()
        hardware.Hardware(gpio)
        self.assertEqual(gpio.modes, {17: "OUT", 27: "OUT", 22: "IN"})
        self.assertEqual(gpio.pulls[22], "PUD_UP")


class ZyklusTest(unittest.TestCase):
    def test_dry_soil_waters(self):
        gpio = FakeGPIO()
        waits = []
        self.assertTrue(steuerung.zyklus(hardware.Hardware(gpio), 20.0, SETTINGS, waits.append))
        self.assertEqual(waits, [20])
        self.assertIn((17, 1), gpio.outputs)
        self.assertEqual(gpio.outputs[-2:], [(17, 0), (27, 0)])

    def test_wet_soil_does_not_water(self):
        gpio = FakeGPIO()
        self.assertFalse(steuerung.zyklus(hardware.Hardware(gpio), 60.0, SETTINGS, lambda s: None))
        self.assertEqual(gpio.outputs, [])

    def test_button_waters(self):
        gpio = FakeGPIO({22: 0})
        self.assertTrue(steuerung.zyklus(hardware.Hardware(gpio), 60.0, SETTINGS, lambda s: None))


if __name__ == "__main__":
    unittest.main()

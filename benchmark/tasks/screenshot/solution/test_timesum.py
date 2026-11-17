"""Tests for timesum.py. Run with: python test_timesum.py"""
import unittest

from timesum import format_minutes, main, parse_duration


class TimesumTest(unittest.TestCase):
    def test_parse(self):
        self.assertEqual(parse_duration("2h"), 120)
        self.assertEqual(parse_duration("45m"), 45)
        self.assertEqual(parse_duration("1h30m"), 90)
        self.assertEqual(parse_duration(" 1H5M "), 65)

    def test_parse_clock_and_decimal(self):
        self.assertEqual(parse_duration("2:45"), 165)
        self.assertEqual(parse_duration("0.5h"), 30)

    def test_parse_rejects(self):
        for text in ["", "h", "abc", "30", "1h30", "-5m"]:
            with self.assertRaises(ValueError):
                parse_duration(text)

    def test_format(self):
        self.assertEqual(format_minutes(0), "0h 0m")
        self.assertEqual(format_minutes(45), "0h 45m")
        self.assertEqual(format_minutes(100), "1h 40m")

    def test_main(self):
        self.assertEqual(main(["30m", "15m"]), 0)
        self.assertEqual(main(["30m", "soon"]), 1)
        self.assertEqual(main([]), 2)


if __name__ == "__main__":
    unittest.main()

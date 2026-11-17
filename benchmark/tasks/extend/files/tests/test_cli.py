"""Tests for the command line."""
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent


def cli(datafile, *args):
    return subprocess.run([sys.executable, "-m", "inventory", datafile, *args], cwd=ROOT, capture_output=True, text=True)


class CliTest(unittest.TestCase):
    def test_commands(self):
        with tempfile.TemporaryDirectory() as folder:
            data = os.path.join(folder, "data.json")
            self.assertEqual(cli(data, "add", "Bolt", "12").returncode, 0)
            self.assertEqual(cli(data, "add", "nut", "3").returncode, 0)
            self.assertEqual(cli(data, "remove", "bolt", "2").returncode, 0)
            self.assertEqual(cli(data, "stock", "bolt").stdout.strip(), "10")
            self.assertEqual(cli(data, "list").stdout.split(), ["bolt", "10", "nut", "3"])
            self.assertEqual(cli(data, "low").stdout.split(), ["nut", "3"])

    def test_error(self):
        with tempfile.TemporaryDirectory() as folder:
            data = os.path.join(folder, "data.json")
            cli(data, "add", "bolt", "1")
            result = cli(data, "remove", "bolt", "5")
            self.assertEqual(result.returncode, 1)
            self.assertTrue(result.stderr.startswith("error: "))
            self.assertEqual(result.stdout, "")
            self.assertEqual(cli(data, "stock", "bolt").stdout.strip(), "1")


if __name__ == "__main__":
    unittest.main()

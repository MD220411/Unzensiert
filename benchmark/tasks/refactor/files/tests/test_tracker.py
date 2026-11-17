"""Tests for the tracker modules."""
import csv
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

from tracker import export, projects, stats, tags, tasks

ROOT = pathlib.Path(__file__).resolve().parent.parent


class TrackerTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.folder.name, "data.json")

    def tearDown(self):
        self.folder.cleanup()

    def test_projects(self):
        projects.add_project(self.path, "home")
        projects.add_project(self.path, "garden")
        self.assertEqual(projects.list_projects(self.path), ["garden", "home"])
        with self.assertRaises(ValueError):
            projects.add_project(self.path, "home")
        tasks.add_task(self.path, "mow", "garden")
        with self.assertRaises(ValueError):
            projects.remove_project(self.path, "garden")
        projects.remove_project(self.path, "home")
        self.assertEqual(projects.list_projects(self.path), ["garden"])

    def test_tasks(self):
        self.assertEqual(tasks.list_tasks(self.path), [])
        first = tasks.add_task(self.path, " write report ")
        second = tasks.add_task(self.path, "call bank")
        self.assertEqual((first, second), (1, 2))
        with self.assertRaises(ValueError):
            tasks.add_task(self.path, "x", "nowhere")
        tasks.complete_task(self.path, first)
        with self.assertRaises(LookupError):
            tasks.complete_task(self.path, 99)
        self.assertEqual([task["title"] for task in tasks.list_tasks(self.path)], ["write report", "call bank"])
        self.assertEqual([task["id"] for task in tasks.list_tasks(self.path, only_open=True)], [2])

    def test_tags(self):
        task_id = tasks.add_task(self.path, "call bank")
        tags.tag_task(self.path, task_id, " Phone ")
        tags.tag_task(self.path, task_id, "phone")
        tags.tag_task(self.path, task_id, "money")
        self.assertEqual(tasks.list_tasks(self.path)[0]["tags"], ["money", "phone"])
        self.assertEqual([task["id"] for task in tags.tasks_with_tag(self.path, "PHONE")], [task_id])
        with self.assertRaises(LookupError):
            tags.tag_task(self.path, 99, "x")

    def test_stats_and_export(self):
        projects.add_project(self.path, "home")
        projects.add_project(self.path, "garden")
        tasks.add_task(self.path, "paint", "home")
        tasks.add_task(self.path, "clean", "home")
        tasks.add_task(self.path, "call bank")
        tasks.complete_task(self.path, 1)
        self.assertEqual(stats.summary(self.path), {"open": 2, "done": 1, "projects": {"home": [1, 2], "garden": [0, 0], "-": [1, 1]}})
        target = os.path.join(self.folder.name, "out.csv")
        self.assertEqual(export.export_csv(self.path, target), 3)
        with open(target, encoding="utf-8", newline="") as handle:
            rows = list(csv.reader(handle))
        self.assertEqual(rows[0], ["id", "title", "project", "done", "tags"])
        self.assertEqual(rows[1], ["1", "paint", "home", "yes", ""])

    def test_command_line(self):
        def cli(*args):
            return subprocess.run([sys.executable, "-m", "tracker", self.path, *args], cwd=ROOT, capture_output=True, text=True)

        self.assertEqual(cli("add-project", "home").returncode, 0)
        self.assertEqual(cli("add", "paint", "--project", "home").stdout.strip(), "1")
        self.assertEqual(cli("tag", "1", "Weekend").returncode, 0)
        self.assertEqual(cli("list").stdout.strip(), "1 [ ] paint (home) #weekend")
        self.assertEqual(cli("done", "1").returncode, 0)
        self.assertEqual(cli("list", "--open").stdout.strip(), "")
        self.assertEqual(cli("stats").stdout.split(), ["open:", "0", "done:", "1", "home:", "0/1"])
        result = cli("done", "7")
        self.assertEqual(result.returncode, 1)
        self.assertTrue(result.stderr.startswith("error: "))


if __name__ == "__main__":
    unittest.main()

You changed files. Go through these points and make up for what is missing before you report the task as done:

- [test] Test: Is there a test for the new logic or the fixed bug that stays in the test files of the project (for example in the folder `tests`)? A check script that you only ran and deleted again does not count: move its cases into a test file. Then run all tests.
- [docs] Documentation: Does the README (or the file in `docs` that covers it) describe the new behaviour, the new commands and options?
- [settings] Settings: Did you write a new fixed value into the code (default name, limit, count, path, also as a constant like `DEFAULT_X = ...`)? If the project has a configuration file, the value belongs there as a new key and is read from there.
- [cleanup] Cleanup: no helper files, no commented-out code, no leftovers of experiments.

If a point does not apply to this task, skip it. If everything is done, change nothing more and give only your short final report.

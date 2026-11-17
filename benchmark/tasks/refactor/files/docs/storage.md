# Change: one place for the data file

Every module of the tracker reads and writes the JSON file on its own, each a little
differently: different encodings, different handling of a missing file, different
formatting. This has already damaged data files with non-ASCII titles. All file access
moves into one module. What the commands and the public functions do stays the same,
except for the points listed here.

## New module `tracker/storage.py`

- `load(path)` returns the content of the data file as a dict.
  - A missing file gives an empty database: `{"tasks": [], "projects": [], "next_id": 1}`.
    This now holds for every command, also for the ones that used to fail without a file.
  - Keys missing in the file are filled in with the values of the empty database.
  - The file is read as UTF-8.
  - A file that is not valid JSON raises `StorageError`, an exception class defined in
    `tracker/storage.py`. Its message contains the path.
- `save(path, data)` writes the data file.
  - UTF-8, non-ASCII characters are written as they are (not as `\u` escapes), indented
    by 2 spaces.
  - The write is atomic: the content goes to a temporary file in the same folder, which
    then replaces the data file with `os.replace`. If the data cannot be written (for
    example because it cannot be converted to JSON), the existing data file stays
    unchanged and no temporary file is left behind.

## The other modules

- `tasks.py`, `projects.py`, `tags.py`, `stats.py` and `export.py` use `storage.load` and
  `storage.save` for the data file. None of them imports `json` or opens the data file
  itself. `export.py` still opens the CSV file it writes.
- Their own helper functions for reading and writing the data file are removed.
- The command line reports a `StorageError` like the other errors (`error: <message>` on
  stderr, exit code 1).

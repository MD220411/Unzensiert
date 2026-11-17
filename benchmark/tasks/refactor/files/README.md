# tracker

Small task tracker for the command line. All data lives in one JSON file.

## Requirements

Python 3.10 or newer, no further packages.

## Usage

```
python -m tracker <datafile> add-project <name>
python -m tracker <datafile> projects
python -m tracker <datafile> add <title> [--project <name>]
python -m tracker <datafile> done <id>
python -m tracker <datafile> tag <id> <tag>
python -m tracker <datafile> list [--open] [--tag <tag>]
python -m tracker <datafile> stats
python -m tracker <datafile> export <file.csv>
```

Errors are printed to stderr as `error: <message>` and end the program with exit code 1.

## Layout

| Path | Purpose |
|---|---|
| `tracker/tasks.py` | create, complete and list tasks |
| `tracker/projects.py` | projects that tasks belong to |
| `tracker/tags.py` | tags on tasks |
| `tracker/stats.py` | numbers about the tasks |
| `tracker/export.py` | CSV export |
| `tracker/__main__.py` | command line |
| `tests/` | tests, run with `python -m unittest discover -s tests` |
| `docs/` | specifications of changes |

## Data file

```json
{
  "tasks": [{"id": 1, "title": "paint", "project": "home", "done": false, "tags": ["weekend"]}],
  "projects": ["home"],
  "next_id": 2
}
```

"""Command line of the tracker: python -m tracker <datafile> <command> ..."""
import argparse
import sys

from tracker import export, projects, stats, storage, tags, tasks


def build_parser():
    """Return the argument parser with all commands."""
    parser = argparse.ArgumentParser(prog="tracker")
    parser.add_argument("datafile")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("add-project").add_argument("name")
    commands.add_parser("projects")
    command = commands.add_parser("add")
    command.add_argument("title")
    command.add_argument("--project")
    commands.add_parser("done").add_argument("id", type=int)
    command = commands.add_parser("tag")
    command.add_argument("id", type=int)
    command.add_argument("tag")
    command = commands.add_parser("list")
    command.add_argument("--open", action="store_true")
    command.add_argument("--tag")
    commands.add_parser("stats")
    commands.add_parser("export").add_argument("file")
    return parser


def format_task(task):
    """Return one line for a task: id, state, title, project and tags."""
    line = f"{task['id']} [{'x' if task['done'] else ' '}] {task['title']}"
    if task["project"]:
        line += f" ({task['project']})"
    for tag in task["tags"]:
        line += f" #{tag}"
    return line


def run(args):
    """Execute one command."""
    path = args.datafile
    if args.command == "add-project":
        projects.add_project(path, args.name)
    elif args.command == "projects":
        for name in projects.list_projects(path):
            print(name)
    elif args.command == "add":
        print(tasks.add_task(path, args.title, args.project))
    elif args.command == "done":
        tasks.complete_task(path, args.id)
    elif args.command == "tag":
        tags.tag_task(path, args.id, args.tag)
    elif args.command == "list":
        found = tags.tasks_with_tag(path, args.tag) if args.tag else tasks.list_tasks(path)
        for task in found:
            if not args.open or not task["done"]:
                print(format_task(task))
    elif args.command == "stats":
        numbers = stats.summary(path)
        print(f"open: {numbers['open']}")
        print(f"done: {numbers['done']}")
        for name in sorted(numbers["projects"]):
            print(f"{name}: {numbers['projects'][name][0]}/{numbers['projects'][name][1]}")
    elif args.command == "export":
        print(export.export_csv(path, args.file))


def main():
    """Parse the command line, run the command and report errors."""
    args = build_parser().parse_args()
    try:
        run(args)
    except (ValueError, LookupError, storage.StorageError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

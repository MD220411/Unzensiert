"""Command line of the inventory tool: python -m inventory <datafile> <command> ..."""
import argparse
import sys

from inventory.config import load_config
from inventory.report import low_stock
from inventory.store import StockError, Store


def build_parser():
    """Return the argument parser with all commands."""
    parser = argparse.ArgumentParser(prog="inventory")
    parser.add_argument("datafile")
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("add", "remove"):
        command = commands.add_parser(name)
        command.add_argument("item")
        command.add_argument("quantity", type=int)
    command = commands.add_parser("stock")
    command.add_argument("item")
    commands.add_parser("list")
    commands.add_parser("low")
    return parser


def run(args):
    """Execute one command."""
    store = Store.load(args.datafile)
    if args.command == "add":
        store.add(args.item, args.quantity)
        store.save(args.datafile)
    elif args.command == "remove":
        store.remove(args.item, args.quantity)
        store.save(args.datafile)
    elif args.command == "stock":
        print(store.stock(args.item))
    elif args.command == "list":
        for item, quantity in store.items():
            print(f"{item} {quantity}")
    elif args.command == "low":
        for item, quantity in low_stock(store, load_config()["lowStockThreshold"]):
            print(f"{item} {quantity}")


def main():
    """Parse the command line, run the command and report errors."""
    args = build_parser().parse_args()
    try:
        run(args)
    except (StockError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

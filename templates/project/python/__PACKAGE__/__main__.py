"""Command line entry point: python -m {{PACKAGE}}"""
import sys

from {{PACKAGE}}.config import load_settings


def main(argv):
    """Run the program with the given arguments and return its exit code."""
    settings = load_settings()
    print(settings["greeting"])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

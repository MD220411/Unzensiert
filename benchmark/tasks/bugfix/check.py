"""Check for the bugfix task. Usage: python -I check.py <workdir>. Exit code 0 = passed."""
import pathlib
import subprocess
import sys

work = pathlib.Path(sys.argv[1])
original = pathlib.Path(__file__).parent / "files" / "test_textstats.py"


def normalized(path):
    return path.read_text(encoding="utf-8").replace("\r\n", "\n").strip()


if normalized(work / "test_textstats.py") != normalized(original):
    print("FAIL: test file was modified")
    sys.exit(1)

run = subprocess.run([sys.executable, "test_textstats.py"], cwd=work, capture_output=True, text=True, timeout=30)
if run.returncode != 0 or "ALL TESTS PASSED" not in run.stdout:
    print("FAIL: tests do not pass\n" + run.stdout[-500:] + run.stderr[-500:])
    sys.exit(1)

# Hidden cases, so that hard-coding the visible test values does not pass.
hidden = (
    "from textstats import average_word_length, most_common, word_count\n"
    "assert word_count('  a   b  ') == 2\n"
    "assert average_word_length('   ') == 0.0\n"
    "assert most_common('b a b a c', 2) == [('a', 2), ('b', 2)]\n"
    "assert most_common('x y y z z z', 1) == [('z', 3)]\n"
)
run = subprocess.run([sys.executable, "-c", hidden], cwd=work, capture_output=True, text=True, timeout=30)
if run.returncode != 0:
    print("FAIL: hidden cases\n" + run.stderr[-500:])
    sys.exit(1)
print("PASS")

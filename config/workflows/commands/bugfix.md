---
description: Fix a bug in fixed steps (first a test that shows the bug, then the fix)
argument-hint: <description of the bug, error message or image file>
---

Fix this bug: $ARGUMENTS

Work through the steps in order and do not skip any.

1. **Reproduce.** Read the description carefully (for an image: every call and every output
   in it). Run exactly the calls it names and note what happens and what is expected
   instead.
2. **Cause.** Find the place in the code that causes the bug, not just the place where it
   becomes visible. Check whether the same cause affects other input.
3. **Test first.** Write a test into the test files of the project that shows the bug, and
   run it: it must fail.
4. **Fix.** Change as little as possible. Do not rebuild anything that is not part of the
   bug.
5. **Check.** The new test and all old ones must pass. Then run the calls from step 1 again
   unchanged and compare with the expected result.
6. **Documentation.** If the README describes the behaviour concerned, update it. If the
   project has a `CHANGELOG.md`, add an entry.
7. **Report.** Briefly: cause, fix, changed files, what is still open.

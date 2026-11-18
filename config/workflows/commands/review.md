---
description: Review the latest changes with fresh eyes, without changing anything
argument-hint: [what to review, otherwise the uncommitted changes]
---

Review changes to this project: $ARGUMENTS

Do not change any file while doing so. If nothing is named above, review the uncommitted
changes (`git status`, `git diff`); if there are none, the last commit (`git show`).

1. **Task.** Find out what the change is meant to do (commit message, `SPEC.md`,
   documentation, what is named above).
2. **Read.** Read every changed file completely, not only the changed lines.
3. **Run.** Start the tests and, if there is one, the check command of the project. Try the
   new calls with an empty, a wrong and a typical input.
4. **Assess.** Look specifically for:
   - errors and edge cases that no test covers,
   - behaviour that worked before and is different now,
   - fixed values in the code that belong in the configuration file,
   - new logic without a test, new behaviour without an entry in the README,
   - duplicated code, helper files, commented-out code.
5. **Report.** A list of findings, the most serious first, for each finding file and line,
   what is wrong and how to show it. Separate what is confirmed (run, seen) from what is
   assumed. If you find nothing, say so and name what you ran.

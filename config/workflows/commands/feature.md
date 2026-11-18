---
description: Build a new feature in fixed steps (requirements, plan, tests, code, docs, check)
argument-hint: <what to build>
---

Build this feature: $ARGUMENTS

Work through the steps in order and do not skip any.

1. **Read.** README, CLAUDE.md and the files concerned. Find out where the tests,
   configuration and documentation of the project are and which command checks it.
2. **Requirements.** Write down in three to eight points how one can tell that the feature
   is finished (acceptance criteria), including the edge cases: empty input, wrong input,
   behaviour for existing calls and files. If the project has a specification, it applies;
   only add what is missing.
3. **Plan.** Name the files you change or create, and what happens in each. New fixed
   values go into the configuration file of the project.
4. **Tests.** Write at least one test for every acceptance criterion into the test files of
   the project.
5. **Code.** Carry out the plan. What worked before must keep working.
6. **Check.** Run the tests and, if there is one, the check command of the project. Fix
   errors until everything passes.
7. **Documentation.** Add the new feature to the README (commands, options, examples); for
   changes to the structure also to the documentation under `docs`. If the project has a
   `CHANGELOG.md`, add an entry.
8. **Report.** Briefly: what was changed, in which files, what is still open.

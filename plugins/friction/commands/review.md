---
description: "Review the open entries in FRICTION.md: group them by root cause, then fix, track, or drop each one with the user's approval"
argument-hint: [filter, e.g. "docker" or "only the retries"]
---

Work through the friction log and sand the project down:

1. Read `FRICTION.md` at the project root. If it is missing or has no open entries, say so and stop. Apply any filter in $ARGUMENTS.
2. Group the open entries by root cause, not by wording: the same flaky command, the same undocumented step, the same stale-state gotcha. Three entries about one setup step are one fix.
3. For each group, propose one outcome:
   - fix: a small change in this repo removes the friction (a task-runner target, a doc line, a default, a clearer error, a cleanup step). Name the change and the check that proves it: the command that used to miss now works.
   - track: real work that needs its own task. Say where it goes (issue, backlog, tracked task); do not start it here.
   - outside: the cause lives outside this repo (a tool cache, the harness, the machine). Give the user the action.
   - drop: one-off, already fixed, or not actionable. Say why.
4. Present the triage as plain text and stop for the user's approval. Do not edit anything before they answer.
5. On approval, apply the fixes one group at a time.
6. Confirm with the user if the outside entries have been resolved or not.
7. Update `FRICTION.md`: remove every resolved entry (fixed, tracked, dropped). Entries the user chose to keep, or outside entries that were not resolved, stay open and untouched.
8. Reply with what was fixed, what was tracked or handed to the user, what was dropped, and the checks you ran.

---
description: Show what each subagent in this session ran on, how long it took, and whether model pins fired
---

Report on the most recent session's subagent runs:

1. Run `${CLAUDE_PLUGIN_ROOT}/bin/report.sh`. Add `--all` when the user asks for today's runs across sessions.
2. Print its output verbatim.
3. Add two lines after it:
   - Whether model pins fired, from the `pins fired` line.
   - Which subagents were largest by `final_ctx`.

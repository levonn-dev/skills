#!/usr/bin/env bash
# Trims test and build runner output on stdin: keeps failure blocks and the tail, drops the rest.
# Output of PASS_THROUGH_LINES or fewer lines passes through untouched. Always exits 0.

set -uo pipefail

# Byte-mode matching so the multibyte symbols in FAILURE_RE match as byte sequences.
export LC_ALL=C

PASS_THROUGH_LINES=80
CONTEXT_AFTER=4
TAIL_LINES=25
MAX_FAILURE_LINES=175
FAILURE_RE='[Ee]rror[: \[]|error TS[0-9]|error CS[0-9]|error MSB|  error  |ERROR|FAIL|[Ff]ailed|\(fail\)|panic:|Traceback|Exception|not ok|✗|×|assert|^[^ ]+\.go:[0-9]+:[0-9]+: '

# The regex goes through the environment so awk does not reprocess its backslashes.
FAILURE_RE="$FAILURE_RE" awk \
  -v pass_through="$PASS_THROUGH_LINES" -v context="$CONTEXT_AFTER" \
  -v tail_lines="$TAIL_LINES" -v max_failure="$MAX_FAILURE_LINES" '
  BEGIN { re = ENVIRON["FAILURE_RE"] }
  { line[NR] = $0 }
  END {
    if (NR == 0) exit
    if (NR <= pass_through) {
      for (i = 1; i <= NR; i++) print line[i]
      exit
    }
    # A failure line and the context lines after it form a failure block.
    for (i = 1; i <= NR; i++) {
      if (line[i] ~ re) {
        last = i + context
        if (last > NR) last = NR
        for (j = i; j <= last; j++) block[j] = 1
      }
    }
    tail_start = NR - tail_lines + 1
    if (tail_start < 1) tail_start = 1
    kept = 0; cut = 0; taken = 0
    for (i = 1; i <= NR; i++) {
      if (i >= tail_start) { keep[i] = 1; kept++ }
      else if (block[i]) {
        if (taken < max_failure) { keep[i] = 1; taken++; kept++ }
        else cut++
      }
    }
    for (i = 1; i <= NR; i++) if (keep[i]) print line[i]
    if (cut > 0)
      printf "[trim-output kept %d of %d lines, %d failure lines cut; rerun without the filter to see everything]\n", kept, NR, cut
    else
      printf "[trim-output kept %d of %d lines; rerun without the filter to see everything]\n", kept, NR
  }
'
exit 0

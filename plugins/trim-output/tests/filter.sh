#!/usr/bin/env bash
# Test runner for bin/trim-output.sh. Feeds generated runner output through the
# filter and checks what survives on stdout, the footer, and the exit status.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="$SCRIPT_DIR/../bin/trim-output.sh"

if [ ! -x "$FILTER" ]; then
  echo "ERROR: filter not found or not executable" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
failures=()

check() {
  local name="$1" ok="$2"
  if [ "$ok" = "1" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failures+=("$name")
  fi
}

# has FILE LINE: the output contains LINE as a whole line.
has() { grep -qxF -- "$2" "$1"; }

# Plain "line N" input of the given length.
plain() { seq 1 "$1" | sed 's/^/line /'; }

# 500 lines with a failure block (FAIL plus 4 detail lines) at each given line.
with_failures() {
  plain 500 | awk -v at="$*" '
    BEGIN { n = split(at, a, " "); for (i = 1; i <= n; i++) s[a[i]] = 1 }
    NR in s { id = NR; k = 0; print "FAIL: test_" id; next }
    k < 4 && id { k++; print "  detail " id "." k; next }
    { print }'
}

# 1. pass_through_small
plain 50 > "$tmp/in1"
"$FILTER" < "$tmp/in1" > "$tmp/out1"
cmp -s "$tmp/in1" "$tmp/out1" && ! grep -q '\[trim-output' "$tmp/out1"
check pass_through_small $(( $? == 0 ))

# 2. keeps_failure_blocks_and_tail
with_failures 100 250 400 | "$FILTER" > "$tmp/out2"
ok=1
for n in 100 250 400; do
  has "$tmp/out2" "FAIL: test_$n" || ok=0
  has "$tmp/out2" "  detail $n.4" || ok=0
done
has "$tmp/out2" "line 476" || ok=0
has "$tmp/out2" "line 500" || ok=0
has "$tmp/out2" "line 99" && ok=0
has "$tmp/out2" "line 300" && ok=0
[ "$(tail -n 1 "$tmp/out2")" = "[trim-output kept 40 of 500 lines; rerun without the filter to see everything]" ] || ok=0
check keeps_failure_blocks_and_tail "$ok"

# 3. tail_only_without_failures
plain 500 | "$FILTER" > "$tmp/out3"
ok=1
for n in $(seq 476 500); do has "$tmp/out3" "line $n" || ok=0; done
has "$tmp/out3" "line 475" && ok=0
grep -qF 'kept 25 of 500 lines;' "$tmp/out3" || ok=0
check tail_only_without_failures "$ok"

# 4. order_preserved
a="$(grep -nxF 'FAIL: test_100' "$tmp/out2" | cut -d: -f1)"
b="$(grep -nxF 'FAIL: test_250' "$tmp/out2" | cut -d: -f1)"
c="$(grep -nxF 'FAIL: test_400' "$tmp/out2" | cut -d: -f1)"
d="$(grep -nxF 'line 476' "$tmp/out2" | cut -d: -f1)"
[ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] && [ -n "$d" ] && [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ] && [ "$c" -lt "$d" ]
check order_preserved $(( $? == 0 ))

# 5. overlap_counted_once
plain 500 | sed '490s/.*/FAIL: late/' | "$FILTER" > "$tmp/out5"
ok=1
grep -qF 'kept 25 of 500 lines;' "$tmp/out5" || ok=0
[ "$(grep -cxF 'FAIL: late' "$tmp/out5")" = "1" ] || ok=0
check overlap_counted_once "$ok"

# 6. cap_keeps_tail (296 ERROR lines plus 4 context lines make 300 block lines)
{ seq 1 296 | sed 's/^/ERROR /'; seq 297 500 | sed 's/^/line /'; } | "$FILTER" > "$tmp/out6"
ok=1
has "$tmp/out6" "ERROR 1" || ok=0
has "$tmp/out6" "ERROR 175" || ok=0
has "$tmp/out6" "ERROR 176" && ok=0
for n in $(seq 476 500); do has "$tmp/out6" "line $n" || ok=0; done
[ "$(tail -n 1 "$tmp/out6")" = "[trim-output kept 200 of 500 lines, 125 failure lines cut; rerun without the filter to see everything]" ] || ok=0
check cap_keeps_tail "$ok"

# 7. no_trailing_newline
{ plain 99; printf 'line 100'; } | "$FILTER" > "$tmp/out7"
ok=1
[ "$(tail -n 1 "$tmp/out7")" = "[trim-output kept 25 of 100 lines; rerun without the filter to see everything]" ] || ok=0
[ "$(tail -c 1 "$tmp/out7" | od -An -c | tr -d ' ')" = '\n' ] || ok=0
check no_trailing_newline "$ok"

# 8. empty_input
"$FILTER" < /dev/null > "$tmp/out8"
rc=$?
[ "$rc" = "0" ] && [ ! -s "$tmp/out8" ]
check empty_input $(( $? == 0 ))

# 9. exit_status_survives
bash -c "set -o pipefail; { bash -c 'seq 1 100; exit 3'; } 2>&1 | '$FILTER'" > /dev/null
check exit_status_survives $(( $? == 3 ))

# 10. tsc_errors_kept
plain 500 | sed -e '20s/.*/src\/x.ts(3,7): error TS2304: Cannot find name a/' -e '21s/.*/src\/x.ts(3,7): error TS2304: Cannot find name b/' -e '22s/.*/src\/x.ts(3,7): error TS2304: Cannot find name c/' | "$FILTER" > "$tmp/out10"
ok=1
[ "$(grep -c 'error TS2304' "$tmp/out10")" = "3" ] || ok=0
check tsc_errors_kept "$ok"

# 11. go_vet_diagnostics_kept
{ plain 30; printf './main.go:5:2: undefined: foo\n./main.go:9:4: undefined: bar\n'; seq 33 500 | sed 's/^/line /'; echo 'FAIL pkg [build failed]'; } | "$FILTER" > "$tmp/out11"
ok=1
has "$tmp/out11" "./main.go:5:2: undefined: foo" || ok=0
has "$tmp/out11" "./main.go:9:4: undefined: bar" || ok=0
check go_vet_diagnostics_kept "$ok"

total=$((pass + fail))
if [ "$fail" -gt 0 ]; then
  for f in "${failures[@]}"; do echo "FAIL: $f"; done
fi
echo "Passed: $pass / $total"
[ "$fail" -eq 0 ] || exit 1

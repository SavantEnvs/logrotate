#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# Run upstream's own test scripts (test/test-NNNN.sh) against the logrotate binary build.sh produced in
# mayhem/build-tests. Each script drives logrotate and diffs rotated file names/sizes/contents; exit 77 = skipped.
TEST_DIR="$SRC/mayhem/build-tests/test"
LOGROTATE="$SRC/mayhem/build-tests/logrotate"
[ -x "$LOGROTATE" ] || { echo "missing $LOGROTATE: mayhem/build.sh did not build it" >&2; emit_ctrf "logrotate-test-scripts" 0 1 0; exit 1; }
[ -d "$TEST_DIR" ] || { echo "missing $TEST_DIR: mayhem/build.sh did not prepare it" >&2; emit_ctrf "logrotate-test-scripts" 0 1 0; exit 1; }

cd "$TEST_DIR"
export LOGROTATE
passed=0; failed=0; skipped=0
for t in test-[0-9][0-9][0-9][0-9].sh; do
  rm -rf "${t%.sh}"
  timeout 300 sh "./$t" >"${t%.sh}.log" 2>&1
  rc=$?
  case $rc in
    0)  passed=$((passed+1)) ;;
    77) skipped=$((skipped+1)) ;;
    *)  failed=$((failed+1)); echo "FAIL: $t (exit $rc)" >&2 ;;
  esac
  rm -rf "${t%.sh}"
done
echo "logrotate tests: passed=$passed failed=$failed skipped=$skipped"

# A hollow run must not look green: every committed test script has to have been run.
expected=$(ls "$SRC"/test/test-[0-9][0-9][0-9][0-9].sh | wc -l)
if [ $((passed + failed + skipped)) -ne "$expected" ]; then
  echo "ran $((passed + failed + skipped)) test scripts, upstream ships $expected" >&2
  failed=$((failed+1))
fi
emit_ctrf "logrotate-test-scripts" "$passed" "$failed" "$skipped"

#!/usr/bin/env bash
#MISE description="Run the Swift benchmarks once, print the numbers, and fail when one is worse than its committed threshold; macOS only"
# Benchmarks/Thresholds holds the p90 of each benchmark on the CI runner. One run is stored as the
# baseline named run, and the numbers and the threshold check both read it, so nothing runs twice.
# The tool shows its progress for each benchmark while it runs, in CI too. build/bench/ keeps the two
# tables for the job summary. `update` runs the benchmarks again and writes new thresholds.
#
# The tool prints in blocks unless its output is a terminal, so the run goes through script, which
# gives it one. A benchmark that is better than its threshold by more than the allowed percentage
# makes the plugin fail with the error benchmarkThresholdImprovement, which swift reports as exit
# status 1, like a regression, so the check reads the error's name from its stderr.
set -euo pipefail
root=${MISE_PROJECT_ROOT:?}
cd "$root/Benchmarks"
mode=${1:-check}
shift || true
out=$root/build/bench
mkdir -p "$out"

case "$mode" in
  check)
    script -q /dev/null swift package --allow-writing-to-directory .benchmarkBaselines/ benchmark baseline update run "$@"
    swift package benchmark baseline read run --format markdown | tee "$out/numbers.md"
    status=0
    swift package benchmark thresholds check run --format markdown 2>"$out/check.err" | tee "$out/check.md" || status=$?
    cat "$out/check.err" >&2
    if [ "$status" -ne 0 ] && grep -qx 'error: benchmarkThresholdImprovement' "$out/check.err"; then
      echo "▲ a benchmark is better than its threshold; commit new thresholds to tighten the gate"
      status=0
    fi
    exit "$status"
    ;;
  update)
    script -q /dev/null swift package --allow-writing-to-package-directory benchmark thresholds update "$@"
    ;;
  *)
    echo "usage: bench:swift [check|update]" >&2
    exit 2
    ;;
esac

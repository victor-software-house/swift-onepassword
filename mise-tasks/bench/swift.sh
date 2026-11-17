#!/usr/bin/env bash
#MISE description="Run the Swift benchmarks once, print the numbers, and fail when one is worse than its committed threshold; macOS only"
# Benchmarks/Thresholds holds the p90 of each benchmark on the CI runner. One run is stored as the
# baseline named run, and the numbers and the threshold check both read it, so nothing runs twice.
# The tool shows a progress bar while it runs; CI passes --no-progress. build/bench/ keeps the two
# tables for the job summary. `update` runs the benchmarks again and writes new thresholds.
set -euo pipefail
root=${MISE_PROJECT_ROOT:?}
cd "$root/Benchmarks"
mode=${1:-check}
shift || true
out=$root/build/bench
mkdir -p "$out"

case "$mode" in
  check)
    swift package --allow-writing-to-directory .benchmarkBaselines/ benchmark baseline update run "$@"
    swift package benchmark baseline read run --format markdown --no-progress | tee "$out/numbers.md"
    # The tool exits 0 when equal, 4 when only better, and 2 or more for a regression or an error.
    status=0
    swift package benchmark baseline check run --check-absolute-path Thresholds --format markdown --no-progress \
      | tee "$out/check.md" || status=$?
    case "$status" in 0 | 4) ;; *) exit "$status" ;; esac
    ;;
  update)
    swift package --allow-writing-to-package-directory benchmark thresholds update "$@"
    ;;
  *)
    echo "usage: bench:swift [check|update]" >&2
    exit 2
    ;;
esac

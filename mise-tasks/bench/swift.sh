#!/usr/bin/env bash
#MISE description="Run the Swift benchmarks once, print the numbers, and fail when one is worse than its committed threshold; macOS only"
# Benchmarks/Thresholds holds the p90 of each benchmark's allocation counts, leaked bytes and resident
# peak on the CI runner; the times are printed without a threshold. One run is stored as the
# baseline named run, and the numbers and the threshold check both read it, so nothing runs twice.
# build/bench/ keeps the two tables for the job summary. `update` writes new thresholds from that
# baseline, so it follows a `check`.
#
# The package's benchmark plugin builds the benchmark tool again on every call, about 40 s each. The
# first call builds the tool and the benchmarks, runs them and stores the baseline; the numbers and
# the check then run the tool it built, with the arguments the plugin passes in 1.38.2. The run goes
# through script, which gives the tool a terminal; with a pipe it prints in blocks, and the progress
# of a benchmark reaches the log only when the run ends. The tool exits 0 when every benchmark is
# within its threshold, 4 when one is better, 2 when one is worse, and 1 or 3 on a failure; a better
# benchmark passes.
set -euo pipefail
root=${MISE_PROJECT_ROOT:?}
cd "$root/Benchmarks"
mode=${1:-check}
shift || true
out=$root/build/bench
mkdir -p "$out"

# The release build of an executable the plugin made, by name.
built() { find .build -type f -name "$1" -perm -u+x -ipath '*release*' -not -path '*/checkouts/*' -not -path '*.dSYM/*' | head -n 1; }
args=(--baseline-storage-path "$PWD" --grouping benchmark --benchmark-package-identifier benchmark --targets OnePasswordBenchmarks)

case "$mode" in
  check)
    script -q /dev/null swift package --force-resolved-versions --allow-writing-to-directory .benchmarkBaselines/ benchmark baseline update run "$@"
    tool=$(built BenchmarkTool)
    exe=$(built OnePasswordBenchmarks)
    "$tool" --command baseline --baseline-operation read --baseline run --format markdown "${args[@]}" \
      | tee "$out/numbers.md"
    status=0
    "$tool" --command thresholds --thresholds-operation check --baseline run --format markdown "${args[@]}" \
      --benchmark-executable-paths "$exe" | tee "$out/check.md" || status=$?
    case "$status" in
      0) ;;
      4) echo "▲ a benchmark is better than its threshold; commit new thresholds to tighten the gate" ;;
      *) exit "$status" ;;
    esac
    ;;
  update)
    tool=$(built BenchmarkTool)
    exe=$(built OnePasswordBenchmarks)
    "$tool" --command thresholds --thresholds-operation update --baseline run --format text "${args[@]}" \
      --benchmark-executable-paths "$exe"
    # The tool writes every metric of the baseline. One with a file entry and no threshold in its benchmark
    # is checked with a limit of zero, so the files keep only the metrics that have a threshold.
    for file in Thresholds/*.json; do
      jq -S 'del(.wallClock)' "$file" >"$file.tmp"
      mv "$file.tmp" "$file"
    done
    ;;
  *)
    echo "usage: bench:swift [check|update]" >&2
    exit 2
    ;;
esac

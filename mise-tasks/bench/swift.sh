#!/usr/bin/env bash
#MISE description="Run the Swift benchmarks and fail when one is worse than its committed threshold; macOS only"
# Benchmarks/Thresholds holds the p90 of each benchmark on the CI runner. Without an argument the
# run is checked against them; `update` writes them from this run.
set -euo pipefail
cd "${MISE_PROJECT_ROOT:?}/Benchmarks"
case "${1:-check}" in
  check) swift package benchmark thresholds check --no-progress --format markdown ;;
  update) swift package --allow-writing-to-package-directory benchmark thresholds update --no-progress ;;
  report) swift package benchmark --no-progress --format markdown ;;
  *) echo "usage: bench:swift [check|update|report]" >&2; exit 2 ;;
esac

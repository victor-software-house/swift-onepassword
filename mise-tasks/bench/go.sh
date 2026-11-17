#!/usr/bin/env bash
#MISE description="Run the Go benchmarks of core/: the cold open, a warm open and the call dispatch; macOS only"
# The test binary is built once and run three times, because linking it takes longer than most of
# the benchmarks. -test.v names each benchmark as it starts. The cold open starts a process for each
# iteration, so it takes a second or three each; it runs once, and the others COUNT times.
set -euo pipefail
root=${MISE_PROJECT_ROOT:?}
mkdir -p "$root/build/bench"
cd "$root/core"
go test -c -o "$root/build/bench/core.test" .
bench=$root/build/bench/core.test
"$bench" -test.v -test.run '^$' -test.bench '^BenchmarkOpenCold$' -test.benchmem -test.count 1
"$bench" -test.v -test.run '^$' -test.bench . -test.skip '^BenchmarkOpenCold$' -test.benchmem -test.count "${COUNT:-3}"
# A client kept for an agent's whole run: the memory after a thousand calls against the start.
"$bench" -test.run '^TestLongLivedClientMemory$' -test.v | grep -E 'start:|end:|^(PASS|FAIL|---)'

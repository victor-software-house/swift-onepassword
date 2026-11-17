#!/usr/bin/env bash
#MISE description="Run the Go benchmarks of core/: the cold open, a warm open and the call dispatch; macOS only"
# The cold open starts a process for each iteration, so it takes a second each.
set -euo pipefail
cd "${MISE_PROJECT_ROOT:?}/core"
go test -run '^$' -bench . -benchmem -count "${COUNT:-3}" ./...

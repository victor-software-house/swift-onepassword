#!/usr/bin/env bash
#MISE description="Run the Go benchmarks of core/: the cold open, a warm open and the call dispatch; macOS only"
# -v names each benchmark as it starts. The cold open starts a process for each iteration, so it
# takes a second or three each.
set -euo pipefail
cd "${MISE_PROJECT_ROOT:?}/core"
go test -v -run '^$' -bench . -benchmem -count "${COUNT:-3}" ./...
# A client kept for an agent's whole run: the memory after a thousand calls against the start.
go test -run '^TestLongLivedClientMemory$' -v ./... | grep -E 'start:|end:|^(ok|FAIL|---)'

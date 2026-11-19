#!/usr/bin/env bash
#MISE description="Run the Go tests of core/ with the race detector, then the memory test alone; macOS only"
set -euo pipefail
cd "${MISE_PROJECT_ROOT:?}/core"
# The race detector adds its own memory to the resident size.
# So the memory test runs alone, with no race detector.
go test -race -skip '^TestLongLivedClientMemory$' ./...
go test -run '^TestLongLivedClientMemory$' ./...

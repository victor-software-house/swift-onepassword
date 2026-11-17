#!/usr/bin/env bash
#MISE description="Run the Go tests of core/ with the race detector; macOS only"
set -euo pipefail
cd "${MISE_PROJECT_ROOT:?}/core"
go test -race ./...

#!/bin/sh
#MISE description="Run the Go tests of core/ with the race detector"
#MISE tools = { go = "1.27.4" }
go -C "${MISE_PROJECT_ROOT:?}/core" test -race ./...

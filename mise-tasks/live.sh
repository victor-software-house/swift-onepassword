#!/usr/bin/env bash
#MISE description="Run the live tests against the test vault; they skip without OP_TEST_SERVICE_ACCOUNT_TOKEN; macOS only"
# The report of the timing test is build/live-report.md. About 45 calls and 70 reads reach 1Password.
set -euo pipefail
cd "${MISE_PROJECT_ROOT:?}"
mkdir -p build
export OP_LIVE_REPORT=$PWD/build/live-report.md
rm -f "$OP_LIVE_REPORT"
swift test --filter LiveTests

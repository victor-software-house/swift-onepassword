#!/usr/bin/env bash
#MISE description="Run the live tests against the test vaults; the read tests skip without OP_TEST_SERVICE_ACCOUNT_TOKEN, the write tests without OP_TEST_WRITE_TOKEN; macOS only"
# The report of the timing test is build/live-report.md. About 45 calls and 70 reads reach 1Password.
set -euo pipefail
cd "${MISE_PROJECT_ROOT:?}"
mkdir -p build
export OP_LIVE_REPORT=$PWD/build/live-report.md
rm -f "$OP_LIVE_REPORT"
# In CI the job summary shows the timings, whether the tests pass or fail.
post_report() {
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ] && [ -f "$OP_LIVE_REPORT" ]; then
    { echo '## Live calls'; echo; cat "$OP_LIVE_REPORT"; } >>"$GITHUB_STEP_SUMMARY"
  fi
}
trap post_report EXIT
swift test --filter LiveTests

#!/usr/bin/env bash
#MISE description="Print the release tag of the binary built from core/ at HEAD"
# The binary is versioned by the content of core/, not by the package version: the tag is core-
# and the first 12 hex digits of the git tree hash of core/.
set -euo pipefail
hash=$(git rev-parse HEAD:core)
echo "core-${hash:0:12}"

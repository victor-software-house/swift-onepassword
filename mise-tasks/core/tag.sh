#!/usr/bin/env bash
#MISE description="Print the release tag of the binary built from core/ at HEAD"
# The content of core/ sets the version of the binary.
# A package version does not set it.
# The tag is core- followed by the first 12 hex digits of the git tree hash of core/.
set -euo pipefail
hash=$(git rev-parse HEAD:core)
echo "core-${hash:0:12}"

#!/usr/bin/env bash
#MISE description="Check that Package.swift pins the tag xcframework:tag prints"
set -euo pipefail

root=${MISE_PROJECT_ROOT:?}
module=COnePassword
want=$(mise run --quiet xcframework:tag)
# The tag in the url of the COnePassword target.
have=$(awk -v module="$module" '
  # The binaryTarget whose name is the module, from its opening line to the
  # line that closes it.
  /\.binaryTarget\(/ { block = 1; target = 0 }
  block && index($0, "name: \"" module "\"") { target = 1 }
  block && target && match($0, /releases\/download\/[^\/]+\//) {
    print substr($0, RSTART + 18, RLENGTH - 19)
  }
  block && /^[[:space:]]*\)/ { block = 0; target = 0 }
' "$root/Package.swift")

if [ "$have" != "$want" ]; then
  echo "Package.swift names ${have:-no release}, but the inputs at HEAD hash to $want." >&2
  echo "Take main and wait for the XCFramework workflow to publish $want." >&2
  echo "Then run mise run xcframework:pin." >&2
  exit 1
fi

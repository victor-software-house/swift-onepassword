#!/bin/sh
#MISE description="Fail when Package.swift names a core release other than the one for core/ at HEAD"
set -eu
want=$(git rev-parse HEAD:core | cut -c1-12)
have=$(sed -nE 's|.*releases/download/core-([0-9a-f]{12})/.*|\1|p' Package.swift)
if [ "$have" != "$want" ]; then
  echo "Package.swift names core-${have:-none}, but core/ at HEAD is core-$want." >&2
  echo "Run mise run core:pin after the Core workflow has published core-$want." >&2
  exit 1
fi

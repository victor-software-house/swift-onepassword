#!/usr/bin/env bash
#MISE description="Pin the COnePassword binaryTarget to the release of xcframework:tag"
#MISE tools = { gh = "2.105.0" }
# Run it after the XCFramework workflow has published that release.
# It downloads the zip and computes its checksum.
# It then rewrites the url and checksum of the binaryTarget named
# COnePassword, and nothing else in Package.swift.
set -euo pipefail

root=${MISE_PROJECT_ROOT:?}
module=COnePassword
repository=victor-software-house/swift-onepassword
tag=$(mise run --quiet xcframework:tag)
asset=$module.xcframework.zip

if ! gh release view "$tag" --repo "$repository" --json assets --jq '.assets[].name' |
  grep -qxF "$asset"; then
  echo "The release $tag has no $asset: wait for the XCFramework workflow, or run it." >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
gh release download "$tag" --repo "$repository" --pattern "$asset" --dir "$work"
checksum=$(swift package compute-checksum "$work/$asset")
url=https://github.com/$repository/releases/download/$tag/$asset

# Fails unless the target has exactly one url and one checksum.
awk -v module="$module" -v url="$url" -v checksum="$checksum" '
  # The binaryTarget whose name is the module, from its opening line to the
  # line that closes it.
  /\.binaryTarget\(/ { block = 1; target = 0 }
  block && index($0, "name: \"" module "\"") { target = 1 }
  block && target && sub(/url: "[^"]*"/, "url: \"" url "\"") { urls++ }
  # swift format puts a url longer than its line limit on the line after url:.
  block && target && wrapped && sub(/"[^"]*"/, "\"" url "\"") { urls++ }
  block && target && sub(/checksum: "[^"]*"/, "checksum: \"" checksum "\"") { sums++ }
  { print; wrapped = block && target && /url:[[:space:]]*$/ }
  block && /^[[:space:]]*\)/ { block = 0; target = 0 }
  END { if (urls != 1 || sums != 1) exit 1 }
' "$root/Package.swift" >"$work/Package.swift" || {
  echo "Package.swift has no binaryTarget named $module with one url and one checksum." >&2
  exit 1
}
cat "$work/Package.swift" >"$root/Package.swift"
echo "pinned $tag $checksum"

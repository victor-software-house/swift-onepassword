#!/usr/bin/env bash
#MISE description="Point Package.swift's binary target at the core release for the current core/ content"
# Reads the release that core.yml published for core/ at HEAD, downloads its zip, and rewrites the
# url and checksum in Package.swift. Run it after core.yml has published the release.
set -euo pipefail

root=${MISE_PROJECT_ROOT:?}
tag=$(mise run --quiet core:tag)
repo=victor-software-house/swift-onepassword
asset=COnePassword.xcframework.zip

gh release view "$tag" --repo "$repo" --json assets --jq '.assets[].name' | grep -qx "$asset" \
  || { echo "release $tag has no $asset; run the Core workflow first" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
gh release download "$tag" --repo "$repo" --pattern "$asset" --dir "$work"
checksum=$(swift package compute-checksum "$work/$asset")

url=https://github.com/$repo/releases/download/$tag/$asset
sed -E \
  -e "s|url: \"https://github.com/$repo/releases/download/[^\"]*\"|url: \"$url\"|" \
  -e "s|checksum: \"[0-9a-f]*\"|checksum: \"$checksum\"|" \
  "$root/Package.swift" > "$work/Package.swift"
mv "$work/Package.swift" "$root/Package.swift"
echo "pinned $tag $checksum"

#!/usr/bin/env bash
#MISE description="Build COnePassword.xcframework.zip from core/; macOS only"
#MISE tools = { go = "1.27.4" }
# Go builds core/ as a C archive for each architecture, lipo
# joins them, and xcodebuild wraps the result with a module map.
# The output is in build/core/: the zip, its checksum and size,
# and an empty notes.md.
#
# A task of xcframework_extra_tasks that reads the build depends on this one.
# It may append lines to notes.md, which the release notes end with.
set -euo pipefail

if [ "$(uname -s)" != Darwin ]; then
  echo "xcframework:build links with Xcode, so it runs on macOS only." >&2
  exit 1
fi

root=${MISE_PROJECT_ROOT:?}
out=$root/build/core
module=COnePassword

rm -rf "$out"
mkdir -p "$out/headers"
: >"$out/notes.md"

cd "$root/core"
for arch in arm64 amd64; do
  case $arch in
    arm64) clang_arch=arm64 ;;
    amd64) clang_arch=x86_64 ;;
  esac
  mkdir -p "$out/$arch"
  GOOS=darwin CGO_ENABLED=1 GOARCH=$arch \
    CC="xcrun clang -arch $clang_arch -mmacosx-version-min=26.0" \
    go build -trimpath -buildmode=c-archive -o "$out/$arch/lib$module.a" .
done

lipo -create "$out/arm64/lib$module.a" "$out/amd64/lib$module.a" -output "$out/lib$module.a"
cp "$out/arm64/lib$module.h" "$out/headers/$module.h"
cat >"$out/headers/module.modulemap" <<MODULEMAP
module $module {
  header "$module.h"
  export *
}
MODULEMAP

xcodebuild -create-xcframework -library "$out/lib$module.a" -headers "$out/headers" \
  -output "$out/$module.xcframework"
ditto -c -k --keepParent "$out/$module.xcframework" "$out/$module.xcframework.zip"

checksum=$(swift package compute-checksum "$out/$module.xcframework.zip")
size=$(stat -f %z "$out/$module.xcframework.zip")
printf '%s\n' "$checksum" >"$out/checksum.txt"
printf '%s\n' "$size" >"$out/size.txt"
echo "checksum=$checksum"
echo "size=$size"

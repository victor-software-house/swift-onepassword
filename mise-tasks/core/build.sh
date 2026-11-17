#!/usr/bin/env bash
#MISE description="Build COnePassword.xcframework.zip from core/ and print its checksum and size; macOS only"
# Go builds core/ as a C archive for each architecture, lipo joins them, and xcodebuild wraps the
# result with a module map. The output is in build/core/.
set -euo pipefail

root=${MISE_PROJECT_ROOT:?}
out=$root/build/core
min=26.0

rm -rf "$out"
mkdir -p "$out/headers"

cd "$root/core"
for arch in arm64 amd64; do
  case $arch in
    arm64) clang_arch=arm64 ;;
    amd64) clang_arch=x86_64 ;;
  esac
  mkdir -p "$out/$arch"
  CGO_ENABLED=1 GOOS=darwin GOARCH=$arch \
    CC="xcrun clang -arch $clang_arch -mmacosx-version-min=$min" \
    go build -trimpath -buildmode=c-archive -o "$out/$arch/onepassword.a" .
done

lipo -create "$out/arm64/onepassword.a" "$out/amd64/onepassword.a" -output "$out/libonepassword.a"
cp "$out/arm64/onepassword.h" "$out/headers/onepassword.h"
cat > "$out/headers/module.modulemap" << 'MODULEMAP'
module COnePassword {
  header "onepassword.h"
  export *
}
MODULEMAP

xcodebuild -create-xcframework -library "$out/libonepassword.a" -headers "$out/headers" \
  -output "$out/COnePassword.xcframework"
ditto -c -k --keepParent "$out/COnePassword.xcframework" "$out/COnePassword.xcframework.zip"

checksum=$(swift package compute-checksum "$out/COnePassword.xcframework.zip")
size=$(stat -f %z "$out/COnePassword.xcframework.zip")
printf '%s\n' "$checksum" > "$out/checksum.txt"
printf '%s\n' "$size" > "$out/size.txt"
echo "checksum=$checksum"
echo "size=$size"

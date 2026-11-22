#!/usr/bin/env bash
#MISE description="Print the release tag: core- and 12 hex digits of the build's input hash"
#MISE tools = { go = "1.27.4" }
# go list reports the packages ./core builds from, for each
# architecture xcframework:build compiles, with the same settings.
# The inputs are the files of those packages that sit in the main module, with
# the module's go.mod and go.sum.
# The union of both architectures counts, so the tag does not depend on the
# host.
#
# The tag hashes the HEAD listing of those files.
# A local run on a branch and the workflow on its commit therefore print the
# same tag.
# Package.swift and the tests are no input, so a pin never changes the tag it
# pins.
set -euo pipefail

dir=core
# go reports physical paths, so the root is one too.
root=$(cd -P "$(git -C "${MISE_PROJECT_ROOT:?}" rev-parse --show-toplevel)" && pwd -P)
cd "$root"

# One line per source file of a package in the main module. $d is a variable
# of the Go template, which go list expands.
# shellcheck disable=SC2016
format='{{if and .Module .Module.Main}}{{$d := .Dir}}'
for field in GoFiles CgoFiles CFiles HFiles SFiles SysoFiles EmbedFiles; do
  format+="{{range .$field}}{{\$d}}/{{.}}{{\"\\n\"}}{{end}}"
done
format+='{{end}}'

inputs=$(mktemp)
trap 'rm -f "$inputs"' EXIT
for arch in arm64 amd64; do
  GOOS=darwin CGO_ENABLED=1 GOARCH=$arch \
    go -C "$dir" list -deps -trimpath -buildmode=c-archive -f "$format" . >>"$inputs"
done
gomod=$(go -C "$dir" list -m -f '{{.GoMod}}')
printf '%s\n' "$gomod" >>"$inputs"
if [ -f "${gomod%.mod}.sum" ]; then
  printf '%s\n' "${gomod%.mod}.sum" >>"$inputs"
fi

hash=$(
  while IFS= read -r path; do
    printf '%s\n' "${path#"$root"/}"
  done <"$inputs" | sort -u | tr '\n' '\0' | xargs -0 git ls-tree HEAD -- | git hash-object --stdin
)
echo "$dir-${hash:0:12}"

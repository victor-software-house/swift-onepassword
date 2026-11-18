#!/bin/sh
#MISE description="Write to GITHUB_OUTPUT the version on HEAD and whether this run released it, so the consumer check runs"
# A push to main releases the version when the version commit is HEAD.
# The check runs only there, because the release's tag then points at HEAD.
# A manual run checks the latest release.
set -eu
read -r version < VERSION
tag=v$version
tagged=$(git ls-remote --tags origin "refs/tags/$tag^{}" | cut -f 1)
if [ "${EVENT_NAME:?}" = workflow_dispatch ]; then
  consume=true
elif [ "$tagged" = "$(git rev-parse HEAD)" ]; then
  consume=true
else
  consume=false
fi
echo "$tag consume=$consume"
printf 'version=%s\nconsume=%s\n' "$version" "$consume" >> "$GITHUB_OUTPUT"

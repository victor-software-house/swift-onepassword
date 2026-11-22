#!/usr/bin/env bash
#MISE description="Time one op_client_open with a malformed token against the built archive; macOS only"
#MISE depends=["xcframework:build"]
# The first client loads 1Password's core, so this is the start-up cost of an app that links the
# archive.
# The call must fail with the authenticationFailed code.
# A run prints the time in milliseconds and the process's peak resident size in MiB.
# It appends the two numbers to build/core/notes.md, which the XCFramework release notes end with.
set -euo pipefail

out=${MISE_PROJECT_ROOT:?}/build/core
clang -arch arm64 -mmacosx-version-min=26.0 -x c - -x none "$out/libCOnePassword.a" -I "$out/headers" \
  -framework CoreFoundation -framework Security -lresolv -o "$out/measure" << 'C'
#include <stdio.h>
#include <string.h>
#include <sys/resource.h>
#include <time.h>
#include "COnePassword.h"

int main(void) {
  struct timespec start, end;
  clock_gettime(CLOCK_MONOTONIC, &start);
  char *response = op_client_open("not-a-token", "swift-onepassword-measure", "0");
  clock_gettime(CLOCK_MONOTONIC, &end);
  int authentication = strstr(response, "\"code\":\"authenticationFailed\"") != NULL;
  op_free(response);
  if (!authentication) {
    fprintf(stderr, "a malformed token did not give the authenticationFailed code\n");
    return 1;
  }
  double ms = (end.tv_sec - start.tv_sec) * 1e3 + (end.tv_nsec - start.tv_nsec) / 1e6;
  struct rusage usage;
  getrusage(RUSAGE_SELF, &usage);
  // ru_maxrss is in bytes on macOS.
  printf("%.0f %.0f\n", ms, usage.ru_maxrss / 1048576.0);
  return 0;
}
C
read -r startup rss < <("$out/measure")
{
  echo "- First client start-up, one \`op_client_open\` with a malformed token: $startup ms"
  echo "- Peak resident size of that process: $rss MiB"
} >> "$out/notes.md"
echo "startup_ms=$startup peak_rss_mib=$rss"

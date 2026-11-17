#!/usr/bin/env bash
#MISE description="Time one op_client_open with a malformed token against the built archive; macOS only"
#MISE depends=["core:build"]
# The first client loads 1Password's core, so this is the start-up cost of an app that links the
# archive. The call must fail with the authentication kind. The time in milliseconds is printed
# and kept in build/core/startup-ms.txt.
set -euo pipefail

out=${MISE_PROJECT_ROOT:?}/build/core
clang -arch arm64 -mmacosx-version-min=26.0 -x c - -x none "$out/libonepassword.a" -I "$out/headers" \
  -framework CoreFoundation -framework Security -lresolv -o "$out/measure" << 'C'
#include <stdio.h>
#include <string.h>
#include <time.h>
#include "onepassword.h"

int main(void) {
  struct timespec start, end;
  clock_gettime(CLOCK_MONOTONIC, &start);
  char *reply = op_client_open("not-a-token", "swift-onepassword-measure", "0");
  clock_gettime(CLOCK_MONOTONIC, &end);
  int authentication = strstr(reply, "\"kind\":\"authentication\"") != NULL;
  op_free(reply);
  if (!authentication) {
    fprintf(stderr, "a malformed token did not give the authentication kind\n");
    return 1;
  }
  double ms = (end.tv_sec - start.tv_sec) * 1e3 + (end.tv_nsec - start.tv_nsec) / 1e6;
  printf("%.0f\n", ms);
  return 0;
}
C
"$out/measure" | tee "$out/startup-ms.txt"

#!/usr/bin/env bash
set -euo pipefail

# Verify the defined external ABI used by FRB's ExternalLibrary.process().
# Inspect the final Mach-O, not Rust archives: some Apple nm versions warn on
# Rust LLVM archive members, and archive presence does not prove process export.
if [[ "$#" != 1 ]]; then
  printf 'Usage: %s <macOS executable>\n' "$0" >&2
  exit 2
fi
executable="$1"
if [[ ! -f "$executable" ]]; then
  printf 'Executable not found: %s\n' "$executable" >&2
  exit 1
fi

# -g selects external symbols; -U excludes undefined references; -j emits names.
# Finish nm before matching so pipefail/SIGPIPE cannot turn success into failure.
if ! symbols="$(xcrun nm -gUj "$executable")"; then
  printf 'Could not inspect macOS executable: %s\n' "$executable" >&2
  exit 1
fi
if ! grep -Fxq '_frb_get_rust_content_hash' <<< "$symbols"; then
  printf 'Missing exported symbol _frb_get_rust_content_hash in %s\n' "$executable" >&2
  exit 1
fi
printf '%s exports _frb_get_rust_content_hash\n' "$executable"

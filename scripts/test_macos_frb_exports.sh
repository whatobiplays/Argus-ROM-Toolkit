#!/usr/bin/env bash
set -euo pipefail

# Exercise checker outcomes without requiring Apple tools on portable CI.
# The xcrun stand-in models nm's defined-external-only output and failures;
# real Mach-O coverage runs below on macOS and in native qualification.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT
mkdir -p "$fixture_dir/bin"
touch "$fixture_dir/app with spaces"
cat > "$fixture_dir/bin/xcrun" <<'STUB'
#!/usr/bin/env bash
[[ "$#" == 3 && "$1" == nm && "$2" == -gUj ]] || exit 90
[[ "$3" == "$EXPECTED_EXECUTABLE" ]] || exit 91
cat "$NM_OUTPUT"
printf '%s' "${NM_WARNING:-}" >&2
exit "${NM_STATUS:-0}"
STUB
chmod +x "$fixture_dir/bin/xcrun"
export NM_OUTPUT="$fixture_dir/symbols"
export EXPECTED_EXECUTABLE="$fixture_dir/app with spaces"

assert_result() {
  local expected="$1" message="$2"
  shift 2
  local actual=0 output
  output="$(PATH="$fixture_dir/bin:$PATH" bash "$ROOT_DIR/scripts/check_macos_frb_exports.sh" "$@" 2>&1)" || actual=$?
  if [[ "$actual" != "$expected" || "$output" != *"$message"* ]]; then
    printf 'FAIL: expected status %s and %s; got status %s: %s\n' "$expected" "$message" "$actual" "$output" >&2
    exit 1
  fi
}

printf '_frb_get_rust_content_hash\n' > "$NM_OUTPUT"
assert_result 0 'exports _frb_get_rust_content_hash' "$fixture_dir/app with spaces"
export NM_WARNING='nm: diagnostic warning'
assert_result 0 'exports _frb_get_rust_content_hash' "$fixture_dir/app with spaces"
unset NM_WARNING
# Large captured output must remain exact-match safe without truncation.
awk 'BEGIN { print "_frb_get_rust_content_hash"; for (i=0; i<100000; i++) print "_other_" i }' > "$NM_OUTPUT"
assert_result 0 'exports _frb_get_rust_content_hash' "$fixture_dir/app with spaces"
printf '_other\n' > "$NM_OUTPUT"
assert_result 1 'Missing exported symbol' "$fixture_dir/app with spaces"
printf 'prefix_frb_get_rust_content_hash\n_frb_get_rust_content_hash_suffix\n' > "$NM_OUTPUT"
assert_result 1 'Missing exported symbol' "$fixture_dir/app with spaces"
: > "$NM_OUTPUT"
export NM_WARNING='_frb_get_rust_content_hash'
assert_result 1 'Missing exported symbol' "$fixture_dir/app with spaces"
unset NM_WARNING
printf '_frb_get_rust_content_hash\n' > "$NM_OUTPUT"
export NM_STATUS=7
assert_result 1 'Could not inspect' "$fixture_dir/app with spaces"
unset NM_STATUS
assert_result 1 'Executable not found' "$fixture_dir/missing"
assert_result 2 'Usage:'
assert_result 2 'Usage:' one two

if [[ "$(uname -s)" == Darwin ]]; then
  # Catch accidental inclusion of undefined symbols with actual Apple nm.
  cat > "$fixture_dir/probe.c" <<'C'
extern void frb_get_rust_content_hash(void);
int main(void) { frb_get_rust_content_hash(); return 0; }
C
  xcrun clang "$fixture_dir/probe.c" -Wl,-undefined,dynamic_lookup -o "$fixture_dir/undefined"
  if bash "$ROOT_DIR/scripts/check_macos_frb_exports.sh" "$fixture_dir/undefined"; then
    printf 'FAIL: undefined FRB symbol accepted\n' >&2
    exit 1
  fi
  cat > "$fixture_dir/probe.c" <<'C'
void frb_get_rust_content_hash(void) {}
int main(void) { return 0; }
C
  xcrun clang "$fixture_dir/probe.c" -Wl,-dead_strip,-export_dynamic -o "$fixture_dir/exported"
  bash "$ROOT_DIR/scripts/check_macos_frb_exports.sh" "$fixture_dir/exported"
fi
printf 'macOS FRB export checker tests passed\n'

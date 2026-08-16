#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Required developer tool is missing: %s\n' "$command_name" >&2
    return 1
  fi
}

for command_name in git just rustup fvm bash shellcheck; do
  require_command "$command_name"
done

rust_channel="$(sed -n 's/^channel = "\([^"]*\)"/\1/p' "$ROOT_DIR/rust-toolchain.toml")"
if [[ -z "$rust_channel" ]]; then
  printf 'Could not read Rust channel from rust-toolchain.toml\n' >&2
  exit 1
fi

rustup toolchain install "$rust_channel" \
  --profile minimal \
  --component clippy \
  --component rustfmt

rustup target add --toolchain "$rust_channel" \
  aarch64-linux-android \
  x86_64-linux-android

bash "$ROOT_DIR/scripts/run_rust.sh" cargo fetch --manifest-path "$ROOT_DIR/rust/Cargo.toml" --locked

(
  cd "$ROOT_DIR/flutter"
  fvm install
  fvm flutter pub get --enforce-lockfile
)

if [[ ! -x "$ROOT_DIR/.dart_tool/cargo-ndk/bin/cargo-ndk" ]]; then
  bash "$ROOT_DIR/scripts/run_rust.sh" cargo install cargo-ndk \
    --version 4.1.2 --locked --root "$ROOT_DIR/.dart_tool/cargo-ndk"
fi

printf 'Argus bootstrap complete.\n'

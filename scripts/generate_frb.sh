#!/usr/bin/env bash
set -euo pipefail

# Generate the stable FRB 2.12 bridge without introducing a second production
# Dart dependency graph. FRB 2.12's dependency checker rejects prerelease
# Freezed versions even though this repository's Riverpod analyzer constraints
# require the prerelease already locked by the application. The temporary
# project exists only for the generator's semver check; all outputs remain in
# the checked-in bridge paths configured by flutter_rust_bridge.yaml.

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
generator="$root_dir/.dart_tool/frb/bin/flutter_rust_bridge_codegen"

if [[ ! -x "$generator" ]]; then
  mkdir -p "$root_dir/.dart_tool/frb"
  bash "$root_dir/scripts/run_rust.sh" cargo install \
    flutter_rust_bridge_codegen --version 2.12.0 --locked \
    --root "$root_dir/.dart_tool/frb"
fi

generator_project="$root_dir/.dart_tool/frb/generator_project"
mkdir -p "$generator_project"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/argus-frb.XXXXXX")"
trap 'rm -rf "$temporary_root"' EXIT

printf '%s\n' \
  'name: argus_frb_codegen' \
  'publish_to: none' \
  'environment:' \
  '  sdk: ">=3.11.3 <4.0.0"' \
  'dependencies:' \
  '  flutter_rust_bridge: 2.12.0' \
  '  freezed_annotation: 3.1.0' \
  'dev_dependencies:' \
  '  build_runner: 2.15.1' \
  '  freezed: 3.2.5' \
  > "$generator_project/pubspec.yaml"

(
  cd "$generator_project"
  fvm dart pub get
)

generated_config="$root_dir/flutter_rust_bridge.generated.yaml"
mkdir -p "$(dirname "$generated_config")"
{
  sed \
    -e "s#^rust_root:.*#rust_root: \"rust/crates/argus-bridge\"#" \
    -e "s#^rust_output:.*#rust_output: \"rust/crates/argus-bridge/src/frb_generated.rs\"#" \
    -e "s#^dart_output:.*#dart_output: \"flutter/lib/core/bridge/generated\"#" \
    -e "s#^dart_root:.*#dart_root: \".dart_tool/frb/generator_project\"#" \
    "$root_dir/flutter_rust_bridge.yaml"
} > "$generated_config"

rust_toolchain_bin="$(dirname "$(RUSTUP_TOOLCHAIN=1.97.1 rustup which cargo)")"
(
  cd "$root_dir"
  PATH="$rust_toolchain_bin:$(dirname "$generator"):$PATH" \
    "$generator" generate --config-file "$generated_config"
)
mv "$generated_config" "$temporary_root/flutter_rust_bridge.generated.yaml"

# FRB 2.12 emits Rust that is not always rustfmt-stable. Format through the
# canonical pinned toolchain so `cargo fmt --check` and the generated-source
# drift check agree on committed bytes.
bash "$root_dir/scripts/run_rust.sh" cargo fmt --manifest-path "$root_dir/rust/Cargo.toml" --all

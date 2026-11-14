#!/usr/bin/env bash

# Report the CI directories most likely to consume runner disk space.
# Keeping the list explicit makes the report predictable and avoids broad scans.

usage() {
  printf 'Usage: %s {before-flutter|after-bootstrap|before-check|after-check}\n' "$0" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

case "$1" in
  before-flutter|after-bootstrap|before-check|after-check)
    phase=$1
    ;;
  *)
    usage
    exit 2
    ;;
esac

script_directory=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repository_root=$(cd -P -- "$script_directory/.." && pwd -P)
cd "$repository_root" || exit 1

printf 'CI disk report (phase=%s)\n' "$phase"

report_status=0
cargo_target_directory=
cargo_target_error=

resolve_cargo_target_directory() {
  local toolchain_listing=
  local selected_toolchain=
  local requested_toolchain=
  local installed_toolchain=
  local installed_release=
  local requested_toolchain_installed=false
  local metadata=
  local metadata_status=0

  if ! command -v cargo >/dev/null 2>&1; then
    cargo_target_error='cargo is not installed'
    return 1
  fi

  if command -v rustup >/dev/null 2>&1; then
    toolchain_listing=$(rustup toolchain list 2>/dev/null) || {
      cargo_target_error='rustup could not list installed toolchains'
      return 1
    }
    if [[ -z "$toolchain_listing" ]]; then
      cargo_target_error='no Rust toolchain is installed yet'
      return 1
    fi

    requested_toolchain=${RUSTUP_TOOLCHAIN:-}
    if [[ -z "$requested_toolchain" && -f "$repository_root/rust-toolchain.toml" ]]; then
      requested_toolchain=$(sed -n 's/^[[:space:]]*channel[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$repository_root/rust-toolchain.toml" | head -n 1)
    fi

    if [[ -n "$requested_toolchain" ]]; then
      while IFS= read -r installed_toolchain; do
        installed_toolchain=${installed_toolchain%% *}
        if [[ "$installed_toolchain" == "$requested_toolchain" || "$installed_toolchain" == "$requested_toolchain-"* ]]; then
          selected_toolchain=$requested_toolchain
          requested_toolchain_installed=true
          break
        fi

        if [[ "$requested_toolchain" =~ ^[0-9]+\.[0-9]+$ ]]; then
          installed_release=${installed_toolchain%%-*}
          if [[ "$installed_release" =~ ^${requested_toolchain}\.[0-9]+$ ]]; then
            selected_toolchain=$installed_toolchain
            requested_toolchain_installed=true
            break
          fi
        fi
      done <<<"$toolchain_listing"
    fi

    if [[ "$requested_toolchain_installed" != true ]]; then
      selected_toolchain=$(sed -n 's/^[[:space:]]*\([^[:space:]]*\)[[:space:]]*(default)$/\1/p' <<<"$toolchain_listing" | head -n 1)
      if [[ -z "$selected_toolchain" ]]; then
        selected_toolchain=$(sed -n '1{s/[[:space:]].*//;p}' <<<"$toolchain_listing")
      fi
    fi

    if [[ -z "$selected_toolchain" ]]; then
      cargo_target_error='no installed Rust toolchain is available for Cargo metadata'
      return 1
    fi

    metadata=$(RUSTUP_TOOLCHAIN="$selected_toolchain" cargo metadata \
      --no-deps --format-version 1 \
      --manifest-path "$repository_root/rust/Cargo.toml" \
      --locked --offline 2>/dev/null) || metadata_status=$?
  else
    metadata=$(cargo metadata \
      --no-deps --format-version 1 \
      --manifest-path "$repository_root/rust/Cargo.toml" \
      --locked --offline 2>/dev/null) || metadata_status=$?
  fi

  if [[ $metadata_status -ne 0 ]]; then
    cargo_target_error="cargo metadata exited with status $metadata_status"
    return 1
  fi

  cargo_target_directory=$(printf '%s' "$metadata" | python3 -c '
import json
import sys

try:
    value = json.load(sys.stdin)["target_directory"]
except (KeyError, json.JSONDecodeError, TypeError):
    raise SystemExit(1)
print(value)
' 2>/dev/null) || {
    cargo_target_error='cargo metadata did not return a target directory'
    return 1
  }

  if [[ -z "$cargo_target_directory" ]]; then
    cargo_target_error='cargo metadata returned an empty target directory'
    return 1
  fi
}

if ! resolve_cargo_target_directory; then
  printf '  Cargo target: unavailable (%s)\n' "$cargo_target_error"
  report_status=1
fi

fvm_config_path="$repository_root/flutter/.fvmrc"
project_fvm_cache_path=
project_fvm_git_cache_path=
fvm_config_error=false

read_fvm_config_path() {
  python3 - "$fvm_config_path" "$1" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as config_file:
        config = json.load(config_file)
    value = config.get(sys.argv[2], "")
except (AttributeError, OSError, json.JSONDecodeError):
    raise SystemExit(1)

if value is None:
    value = ""
if not isinstance(value, str):
    raise SystemExit(1)
print(value)
PY
}

if [[ -f "$fvm_config_path" ]]; then
  if ! project_fvm_cache_path=$(read_fvm_config_path cachePath); then
    printf '  FVM project cache: unavailable (.fvmrc could not be read)\n'
    fvm_config_error=true
  fi
  if ! project_fvm_git_cache_path=$(read_fvm_config_path gitCachePath); then
    printf '  FVM project Git cache: unavailable (.fvmrc could not be read)\n'
    fvm_config_error=true
  fi
  if [[ "$fvm_config_error" == true ]]; then
    report_status=1
  fi
fi

resolve_fvm_path() {
  if [[ "$1" == /* ]]; then
    printf '%s' "$1"
  else
    printf '%s/flutter/%s' "$repository_root" "$1"
  fi
}

environment_fvm_cache_path=${FVM_CACHE_PATH:-${FVM_HOME:-}}
if [[ -n "$environment_fvm_cache_path" ]]; then
  environment_fvm_cache_path=$(resolve_fvm_path "$environment_fvm_cache_path")
fi
if [[ -n "$project_fvm_cache_path" ]]; then
  project_fvm_cache_path=$(resolve_fvm_path "$project_fvm_cache_path")
fi
if [[ -n "$project_fvm_git_cache_path" ]]; then
  project_fvm_git_cache_path=$(resolve_fvm_path "$project_fvm_git_cache_path")
fi
effective_fvm_cache_path=$environment_fvm_cache_path
if [[ -z "$effective_fvm_cache_path" ]]; then
  effective_fvm_cache_path=$project_fvm_cache_path
fi
if [[ -z "$effective_fvm_cache_path" && -n "${HOME:-}" ]]; then
  effective_fvm_cache_path="$HOME/fvm"
fi

effective_fvm_git_cache_path=${FVM_GIT_CACHE_PATH:-$project_fvm_git_cache_path}
if [[ -n "${FVM_GIT_CACHE_PATH:-}" ]]; then
  effective_fvm_git_cache_path=$(resolve_fvm_path "$effective_fvm_git_cache_path")
fi
if [[ -z "$effective_fvm_git_cache_path" && -n "$effective_fvm_cache_path" ]]; then
  effective_fvm_git_cache_path="$effective_fvm_cache_path/cache.git"
fi

labels=()
paths=()

add_path() {
  local label=$1
  local path=$2
  if [[ -n "$path" ]]; then
    labels+=("$label")
    paths+=("$path")
  fi
}

add_path 'Cargo target' "$cargo_target_directory"
add_path 'Flutter action SDK' "${FLUTTER_SDK_PATH:-}"
add_path 'Pub cache' "${PUB_CACHE_PATH:-${PUB_CACHE:-${HOME:-}/.pub-cache}}"
if [[ -n "$environment_fvm_cache_path" ]]; then
  add_path 'FVM cache' "$environment_fvm_cache_path"
fi
if [[ -n "$project_fvm_cache_path" ]]; then
  add_path 'FVM project cache' "$project_fvm_cache_path"
fi
if [[ -z "$environment_fvm_cache_path" && -z "$project_fvm_cache_path" ]]; then
  add_path 'FVM cache' "$effective_fvm_cache_path"
fi
if [[ -n "${FVM_GIT_CACHE_PATH:-}" ]]; then
  add_path 'FVM Git cache' "$effective_fvm_git_cache_path"
fi
if [[ -n "$project_fvm_git_cache_path" ]]; then
  add_path 'FVM project Git cache' "$project_fvm_git_cache_path"
fi
if [[ -z "${FVM_GIT_CACHE_PATH:-}" && -z "$project_fvm_git_cache_path" ]]; then
  add_path 'FVM Git cache' "$effective_fvm_git_cache_path"
fi
add_path 'FVM project SDK' "$repository_root/flutter/.fvm/flutter_sdk"
add_path 'cargo-ndk install' "$repository_root/.dart_tool/cargo-ndk"
add_path 'Flutter package metadata' "$repository_root/flutter/.dart_tool"
add_path 'Flutter build output' "$repository_root/flutter/build"

if [[ -z "$effective_fvm_cache_path" ]]; then
  printf '  FVM cache: not configured\n'
fi
if [[ -z "$effective_fvm_git_cache_path" ]]; then
  printf '  FVM Git cache: not configured\n'
fi

seen_paths=()
for index in "${!paths[@]}"; do
  label=${labels[$index]}
  path=${paths[$index]}
  if [[ "$path" != /* ]]; then
    path="$repository_root/$path"
  fi

  if [[ -d "$path" ]]; then
    resolved_path=$(cd -P -- "$path" 2>/dev/null && pwd -P) || resolved_path=$path
    duplicate=false
    for seen_path in "${seen_paths[@]}"; do
      if [[ "$resolved_path" == "$seen_path" ]]; then
        duplicate=true
        break
      fi
    done
    if [[ "$duplicate" == true ]]; then
      continue
    fi
    seen_paths+=("$resolved_path")

    printf '  %s: %s\n' "$label" "$resolved_path"

    filesystem_report=$(df -h "$resolved_path" 2>/dev/null)
    filesystem_status=$?
    if [[ $filesystem_status -eq 0 ]]; then
      filesystem_summary=$(printf '%s\n' "$filesystem_report" | tail -n 1)
      printf '    filesystem: %s\n' "$filesystem_summary"
    else
      printf '    filesystem: unavailable (df exited with status %s)\n' "$filesystem_status"
      report_status=1
    fi

    size_report=$(du -sh "$resolved_path" 2>/dev/null)
    size_status=$?
    if [[ $size_status -eq 0 ]]; then
      printf '    size: %s\n' "$size_report"
    else
      printf '    size: unavailable (du exited with status %s)\n' "$size_status"
      report_status=1
    fi
  else
    printf '  %s: not present (%s)\n' "$label" "$path"
  fi
done

exit "$report_status"

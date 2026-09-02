#!/usr/bin/env bash
set -euo pipefail

ARGUS_MACOS_RUST_TARGET="aarch64-apple-darwin"
ARGUS_MACOS_DEPLOYMENT_TARGET_DEFAULT="11.0"
ARGUS_MACOS_DEPLOYMENT_TARGET_METADATA_PREFIX="argus-macos-deployment-target-"
ARGUS_MACOS_DEPLOYMENT_TARGET_CFLAGS_PREFIX="-DARGUS_MACOS_DEPLOYMENT_TARGET_FINGERPRINT="

# Cargo accepts the target from either the environment or the command line.
# The command-line form wins, matching Cargo's precedence rules for an
# invocation that explicitly names a cross-compilation target.
argus_cargo_target_from_arguments() {
  local target="${CARGO_BUILD_TARGET:-}"
  local expects_target=false
  local argument

  for argument in "$@"; do
    if [[ "$expects_target" == true ]]; then
      target="$argument"
      expects_target=false
      continue
    fi

    case "$argument" in
      --target=*) target="${argument#--target=}" ;;
      --target) expects_target=true ;;
    esac
  done

  printf '%s\n' "$target"
}

argus_cargo_invocation_is_ndk() {
  [[ "${1:-}" == cargo && "${2:-}" == ndk ]]
}

argus_cargo_config_file_has_native_target_rustflags() {
  local config_file="$1"

  [[ -f "$config_file" ]] || return 1

  if awk '
    /^\[target\.aarch64-apple-darwin\][[:space:]]*(#.*)?$/ {
      in_target = 1
      next
    }
    /^\[/ { in_target = 0 }
    in_target && /^[[:space:]]*rustflags[[:space:]]*=/ { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$config_file"; then
    return 0
  fi

  if awk '
    /^\[target\."aarch64-apple-darwin"\][[:space:]]*(#.*)?$/ {
      in_target = 1
      next
    }
    /^\[/ { in_target = 0 }
    in_target && /^[[:space:]]*rustflags[[:space:]]*=/ { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$config_file"; then
    return 0
  fi

  if awk "
    /^\\[target\\.'aarch64-apple-darwin'\\][[:space:]]*(#.*)?$/ {
      in_target = 1
      next
    }
    /^\\[/ { in_target = 0 }
    in_target && /^[[:space:]]*rustflags[[:space:]]*=/ { found = 1 }
    END { exit(found ? 0 : 1) }
  " "$config_file"; then
    return 0
  fi

  local dotted_key
  for dotted_key in \
    "target.aarch64-apple-darwin.rustflags" \
    'target."aarch64-apple-darwin".rustflags' \
    "target.'aarch64-apple-darwin'.rustflags"; do
    if awk -v key="$dotted_key" '
      {
        line = $0
        sub(/[[:space:]]*#.*/, "", line)
        sub(/^[[:space:]]*/, "", line)
        if (index(line, key) == 1) {
          remainder = substr(line, length(key) + 1)
          if (remainder ~ /^[[:space:]]*=/) {
            found = 1
            exit
          }
        }
      }
      END { exit(found ? 0 : 1) }
    ' "$config_file"; then
      return 0
    fi
  done

  return 1
}

argus_cargo_config_argument_has_native_target_rustflags() {
  local expects_config=false
  local argument
  local config_value

  for argument in "$@"; do
    if [[ "$expects_config" == true ]]; then
      config_value="$argument"
      expects_config=false
    elif [[ "$argument" == --config ]]; then
      expects_config=true
      continue
    elif [[ "$argument" == --config=* ]]; then
      config_value="${argument#--config=}"
    else
      continue
    fi

    case "$config_value" in
      target.aarch64-apple-darwin.rustflags=* | \
      'target."aarch64-apple-darwin".rustflags='* | \
      "target.'aarch64-apple-darwin'.rustflags="*)
        return 0
        ;;
    esac

    if [[ -f "$config_value" ]] &&
      argus_cargo_config_file_has_native_target_rustflags "$config_value"; then
      return 0
    fi
  done

  return 1
}

argus_cargo_config_has_native_target_rustflags() {
  if argus_cargo_config_argument_has_native_target_rustflags "$@"; then
    return 0
  fi

  local directory
  local config_file
  directory="$(pwd)"
  while :; do
    for config_file in "$directory/.cargo/config.toml" "$directory/.cargo/config"; do
      if argus_cargo_config_file_has_native_target_rustflags "$config_file"; then
        return 0
      fi
    done

    [[ "$directory" == / ]] && break
    directory="${directory%/*}"
    [[ -n "$directory" ]] || directory=/
  done

  local cargo_home="${CARGO_HOME:-$HOME/.cargo}"
  for config_file in "$cargo_home/config.toml" "$cargo_home/config"; do
    if argus_cargo_config_file_has_native_target_rustflags "$config_file"; then
      return 0
    fi
  done

  return 1
}

# Convert the deployment target into shell-safe bytes for the Cargo metadata
# salt. This keeps an unusual explicit value from becoming executable flag
# text while still making every distinct value a distinct Cargo input.
argus_deployment_target_fingerprint() {
  local deployment_target="$1"

  if [[ -z "$deployment_target" ]]; then
    printf 'empty\n'
    return 0
  fi

  printf '%s' "$deployment_target" |
    LC_ALL=C od -An -v -tx1 |
    tr -d '[:space:]'
  printf '\n'
}

argus_append_space_separated_value() {
  local variable_name="$1"
  local value="$2"
  local marker="$3"
  local existing_value="${!variable_name-}"

  if [[ "$existing_value" == *"$marker"* ]]; then
    return 0
  fi

  if [[ -n "$existing_value" ]]; then
    existing_value+=" "
  fi
  existing_value+="$value"
  printf -v "$variable_name" '%s' "$existing_value"
  export "${variable_name?}"
}

argus_append_space_separated_rustflag() {
  local marker="$2"
  argus_append_space_separated_value "$1" "-C metadata=${marker}" "$marker"
}

argus_append_encoded_rustflag() {
  local marker="$1"
  local separator=$'\x1f'
  local existing_value="${CARGO_ENCODED_RUSTFLAGS-}"

  if [[ "$existing_value" == *"$marker"* ]]; then
    return 0
  fi

  if [[ -n "$existing_value" ]]; then
    existing_value+="$separator"
  fi
  existing_value+="-C${separator}metadata=${marker}"
  export CARGO_ENCODED_RUSTFLAGS="$existing_value"
}

argus_append_native_fingerprint() {
  local fingerprint="$1"
  local marker="${ARGUS_MACOS_DEPLOYMENT_TARGET_CFLAGS_PREFIX}${fingerprint}"

  if declare -p 'CFLAGS_aarch64_apple_darwin' >/dev/null 2>&1; then
    argus_append_space_separated_value \
      CFLAGS_aarch64_apple_darwin "$marker" "$marker"
  else
    argus_append_space_separated_value CFLAGS "$marker" "$marker"
  fi
}

# Configure the environment shared by the Rust compiler and native C build
# scripts. The host parameters are explicit so the contract can be tested on
# a non-macOS machine without pretending that its uname output is different.
argus_configure_macos_rust_build_environment() {
  local host_os="$1"
  local host_arch="$2"
  shift 2

  if [[ "$host_os" != Darwin ]]; then
    return 0
  fi

  if [[ "${1:-}" != cargo ]]; then
    return 0
  fi

  local cargo_target
  cargo_target="$(argus_cargo_target_from_arguments "$@")"

  if argus_cargo_invocation_is_ndk "$@"; then
    return 0
  fi

  if [[ "$cargo_target" == *-apple-darwin &&
    "$cargo_target" != "$ARGUS_MACOS_RUST_TARGET" ]]; then
    printf 'macOS Rust builds support only %s; got %s\n' \
      "$ARGUS_MACOS_RUST_TARGET" "$cargo_target" >&2
    return 1
  fi

  if [[ "$host_arch" != arm64 ]]; then
    if [[ -z "$cargo_target" || "$cargo_target" == "$ARGUS_MACOS_RUST_TARGET" ]]; then
      printf 'macOS Rust builds support Apple Silicon only; host architecture %s is unsupported\n' \
        "$host_arch" >&2
      return 1
    fi
    return 0
  fi

  if [[ -n "$cargo_target" && "$cargo_target" != "$ARGUS_MACOS_RUST_TARGET" ]]; then
    return 0
  fi

  # Native dependency build scripts, including BLAKE3's C compiler setup,
  # consume this value when compiling objects for the arm64 macOS product.
  if [[ -z "${MACOSX_DEPLOYMENT_TARGET:-}" ]]; then
    export MACOSX_DEPLOYMENT_TARGET="$ARGUS_MACOS_DEPLOYMENT_TARGET_DEFAULT"
  fi

  local deployment_target_fingerprint
  deployment_target_fingerprint="$(argus_deployment_target_fingerprint "$MACOSX_DEPLOYMENT_TARGET")"

  local deployment_target_marker
  deployment_target_marker="${ARGUS_MACOS_DEPLOYMENT_TARGET_METADATA_PREFIX}${deployment_target_fingerprint}"

  # Cargo 1.97.1 gives encoded environment flags and RUSTFLAGS precedence over
  # lower configuration sources. Matching target-specific environment flags
  # combine with matching target configuration, while target configuration
  # otherwise outranks build.rustflags. CARGO_BUILD_RUSTFLAGS combines with
  # build.rustflags when no higher source is active. Add the fingerprint to
  # the highest effective source so caller flags remain effective.
  if declare -p CARGO_ENCODED_RUSTFLAGS >/dev/null 2>&1; then
    argus_append_encoded_rustflag "$deployment_target_marker"
  elif declare -p RUSTFLAGS >/dev/null 2>&1; then
    argus_append_space_separated_rustflag RUSTFLAGS "$deployment_target_marker"
    if declare -p CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS >/dev/null 2>&1; then
      argus_append_space_separated_rustflag \
        CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS "$deployment_target_marker"
    fi
  elif declare -p CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS >/dev/null 2>&1 ||
    argus_cargo_config_has_native_target_rustflags "$@"; then
    argus_append_space_separated_rustflag \
      CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS "$deployment_target_marker"
  else
    argus_append_space_separated_rustflag CARGO_BUILD_RUSTFLAGS "$deployment_target_marker"
  fi

  # Cargo's Rust fingerprint does not make cc-rs rebuild merely because
  # MACOSX_DEPLOYMENT_TARGET changed. cc-rs does track CFLAGS, so this unused
  # hexadecimal preprocessor definition makes every affected native build
  # script observe the same deployment-target transition without changing
  # the caller's compiler flags or warning policy.
  argus_append_native_fingerprint "$deployment_target_fingerprint"
}

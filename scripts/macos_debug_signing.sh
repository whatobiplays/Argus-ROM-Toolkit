#!/usr/bin/env bash

# Shared signing preflight for the macOS native qualification harnesses.
#
# The repository keeps owner-specific signing values in the ignored
# Debug.local.xcconfig. Environment variables remain available as a narrow
# automation seam, including for a provisioned CI/self-hosted runner.

_argus_read_xcconfig_value() {
  local key="$1"
  local config_path="$2"
  local value
  value="$(sed -n -E "s|^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(.*)$|\1|p" \
    "$config_path" | tail -n 1)"
  printf '%s' "$value" | sed -E \
    's/[[:space:]]*\/\/.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//; s/^"(.*)"$/\1/'
}

argus_configure_macos_debug_signing() {
  local root_dir="$1"
  local debug_signing_config="$root_dir/flutter/macos/Runner/Configs/Debug.local.xcconfig"
  local identity="${FLUTTER_XCODE_CODE_SIGN_IDENTITY:-}"
  local team="${FLUTTER_XCODE_DEVELOPMENT_TEAM:-}"
  local style="${FLUTTER_XCODE_CODE_SIGN_STYLE:-Automatic}"

  if [[ -f "$debug_signing_config" ]]; then
    local configured_identity
    configured_identity="$(_argus_read_xcconfig_value CODE_SIGN_IDENTITY "$debug_signing_config")"
    if [[ -n "$configured_identity" ]]; then
      identity="$configured_identity"
    fi

    local configured_team
    configured_team="$(_argus_read_xcconfig_value DEVELOPMENT_TEAM "$debug_signing_config")"
    if [[ -n "$configured_team" ]]; then
      team="$configured_team"
    fi

    local configured_style
    configured_style="$(_argus_read_xcconfig_value CODE_SIGN_STYLE "$debug_signing_config")"
    if [[ -n "$configured_style" ]]; then
      style="$configured_style"
    fi
  fi

  if [[ -z "$identity" || -z "$team" ]]; then
    printf 'Stable macOS Debug signing is required for native qualification.\n' >&2
    printf 'Create the ignored local override at:\n  %s\n' \
      "$debug_signing_config" >&2
    printf 'with owner-local values such as:\n' >&2
    printf '  CODE_SIGN_IDENTITY = Apple Development\n' >&2
    printf '  DEVELOPMENT_TEAM = YOUR_TEAM_IDENTIFIER\n' >&2
    printf '  CODE_SIGN_STYLE = Automatic\n' >&2
    return 1
  fi
  if [[ "$identity" != "Apple Development"* ]]; then
    printf 'Native qualification requires an Apple Development signing identity.\n' >&2
    printf 'Update %s without adding owner-specific values to tracked files.\n' \
      "$debug_signing_config" >&2
    return 1
  fi

  export FLUTTER_XCODE_CODE_SIGN_IDENTITY="$identity"
  export FLUTTER_XCODE_DEVELOPMENT_TEAM="$team"
  export FLUTTER_XCODE_CODE_SIGN_STYLE="$style"
}

argus_verify_macos_debug_signature() {
  local app_path="$1"
  local expected_team="${2:-${FLUTTER_XCODE_DEVELOPMENT_TEAM:-}}"
  if [[ ! -d "$app_path" ]]; then
    printf 'Expected macOS Debug app was not built: %s\n' "$app_path" >&2
    return 1
  fi
  if [[ -z "$expected_team" ]]; then
    printf 'A configured macOS development team is required for signature verification.\n' >&2
    return 1
  fi

  local verification_details
  if ! verification_details="$(codesign --verify --deep --strict "$app_path" 2>&1)"; then
    printf 'macOS Debug app failed strict code-signature verification.\n' >&2
    printf '%s\n' "$verification_details" >&2
    return 1
  fi

  local signature_details
  if ! signature_details="$(codesign -d --verbose=4 "$app_path" 2>&1)"; then
    printf 'Unable to inspect the macOS Debug app signature.\n' >&2
    return 1
  fi

  local bundle_identifier
  bundle_identifier="$(printf '%s\n' "$signature_details" | sed -n 's/^Identifier=//p')"
  local team_identifier
  team_identifier="$(printf '%s\n' "$signature_details" | sed -n 's/^TeamIdentifier=//p')"
  if [[ "$bundle_identifier" != "dev.argusromtoolkit.argus" ]]; then
    printf 'Unexpected macOS Debug bundle identifier: %s\n' \
      "$bundle_identifier" >&2
    return 1
  fi
  if ! printf '%s\n' "$signature_details" | grep -q '^Authority=Apple Development:'; then
    printf 'macOS Debug app is not Apple Development signed.\n' >&2
    return 1
  fi
  if [[ -z "$team_identifier" || "$team_identifier" == "not set" ]]; then
    printf 'macOS Debug app has no TeamIdentifier; stable signing is required.\n' >&2
    return 1
  fi
  if [[ "$team_identifier" != "$expected_team" ]]; then
    printf 'macOS Debug app TeamIdentifier does not match the configured development team.\n' >&2
    return 1
  fi
  printf 'Verified stable Apple Development signing for macOS native qualification\n'
}

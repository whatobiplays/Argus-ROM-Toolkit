#!/usr/bin/env bash
set -euo pipefail

ARGUS_MACOS_RUST_TARGET="aarch64-apple-darwin"
ARGUS_MACOS_DEPLOYMENT_TARGET_DEFAULT="11.0"
ARGUS_MACOS_DEPLOYMENT_TARGET_METADATA_PREFIX="argus-macos-deployment-target-"
ARGUS_MACOS_DEPLOYMENT_TARGET_CFLAGS_PREFIX="-DARGUS_MACOS_DEPLOYMENT_TARGET_FINGERPRINT="
ARGUS_MACOS_ENV_ASSIGNMENTS=()
ARGUS_MACOS_TARGET_CFG_OUTPUT=""
ARGUS_MACOS_TARGET_CFG_OUTPUT_LOADED=false
ARGUS_CARGO_CONFIG_VISITED=()
ARGUS_CFG_PARSE_TEXT=""
ARGUS_CFG_PARSE_INDEX=0
ARGUS_CFG_PARSE_RESULT=false
ARGUS_CFG_PARSE_VALID=true

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

# Resolve the cfg facts with the same pinned Rust toolchain that the wrapper
# will use for Cargo. This lets the helper identify target cfg tables without
# reimplementing target properties or changing Cargo's own flag merge order.
argus_load_macos_target_cfg_output() {
  if [[ "$ARGUS_MACOS_TARGET_CFG_OUTPUT_LOADED" == true ]]; then
    return 0
  fi

  local cfg_output
  if [[ -n "${ARGUS_MACOS_RUST_CHANNEL:-}" ]] &&
    command -v rustup >/dev/null 2>&1; then
    if ! cfg_output="$(
      RUSTUP_TOOLCHAIN="$ARGUS_MACOS_RUST_CHANNEL" \
        rustup run "$ARGUS_MACOS_RUST_CHANNEL" rustc --print cfg \
        --target "$ARGUS_MACOS_RUST_TARGET"
    )"; then
      printf 'Could not inspect cfg values for %s with Rust toolchain %s\n' \
        "$ARGUS_MACOS_RUST_TARGET" "$ARGUS_MACOS_RUST_CHANNEL" >&2
      return 1
    fi
  elif command -v rustc >/dev/null 2>&1; then
    if ! cfg_output="$(rustc --print cfg --target "$ARGUS_MACOS_RUST_TARGET")"; then
      printf 'Could not inspect cfg values for %s\n' \
        "$ARGUS_MACOS_RUST_TARGET" >&2
      return 1
    fi
  else
    printf 'Cannot inspect cfg values for %s: rustc is unavailable\n' \
      "$ARGUS_MACOS_RUST_TARGET" >&2
    return 1
  fi

  ARGUS_MACOS_TARGET_CFG_OUTPUT="$cfg_output"
  ARGUS_MACOS_TARGET_CFG_OUTPUT_LOADED=true
}

argus_cfg_predicate_matches_target() {
  local predicate="$1"
  predicate="$(printf '%s' "$predicate" | tr -d '[:space:]')"

  # Cargo exposes the selected target name in cfg expressions, while rustc's
  # --print cfg output contains the individual target properties.
  if [[ "$predicate" == 'target="aarch64-apple-darwin"' ]]; then
    return 0
  fi

  argus_load_macos_target_cfg_output || return 1
  if printf '%s\n' "$ARGUS_MACOS_TARGET_CFG_OUTPUT" |
    grep -Fqx "$predicate"; then
    return 0
  fi

  return 1
}

argus_cfg_skip_whitespace() {
  local text_length="${#ARGUS_CFG_PARSE_TEXT}"
  local character

  while (( ARGUS_CFG_PARSE_INDEX < text_length )); do
    character="${ARGUS_CFG_PARSE_TEXT:ARGUS_CFG_PARSE_INDEX:1}"
    case "$character" in
      [[:space:]]) ARGUS_CFG_PARSE_INDEX=$((ARGUS_CFG_PARSE_INDEX + 1)) ;;
      *) return 0 ;;
    esac
  done
}

argus_cfg_parse_predicate() {
  local text_length="${#ARGUS_CFG_PARSE_TEXT}"
  local start_index="$ARGUS_CFG_PARSE_INDEX"
  local nesting=0
  local character

  while (( ARGUS_CFG_PARSE_INDEX < text_length )); do
    character="${ARGUS_CFG_PARSE_TEXT:ARGUS_CFG_PARSE_INDEX:1}"
    case "$character" in
      ','|')')
        if (( nesting == 0 )); then
          break
        fi
        nesting=$((nesting - 1))
        ARGUS_CFG_PARSE_INDEX=$((ARGUS_CFG_PARSE_INDEX + 1))
        ;;
      '(')
        nesting=$((nesting + 1))
        ARGUS_CFG_PARSE_INDEX=$((ARGUS_CFG_PARSE_INDEX + 1))
        ;;
      *)
        ARGUS_CFG_PARSE_INDEX=$((ARGUS_CFG_PARSE_INDEX + 1))
        ;;
    esac
  done

  if (( nesting != 0 )); then
    ARGUS_CFG_PARSE_VALID=false
    ARGUS_CFG_PARSE_RESULT=false
    return 0
  fi

  local predicate="${ARGUS_CFG_PARSE_TEXT:start_index:ARGUS_CFG_PARSE_INDEX-start_index}"
  predicate="$(printf '%s' "$predicate" | tr -d '[:space:]')"
  if [[ -z "$predicate" ]]; then
    ARGUS_CFG_PARSE_VALID=false
    ARGUS_CFG_PARSE_RESULT=false
  elif argus_cfg_predicate_matches_target "$predicate"; then
    ARGUS_CFG_PARSE_RESULT=true
  else
    ARGUS_CFG_PARSE_RESULT=false
  fi
}

argus_cfg_parse_list() {
  local operation="$1"
  ARGUS_CFG_PARSE_INDEX=$((ARGUS_CFG_PARSE_INDEX + 4))

  local aggregate=true
  if [[ "$operation" == any ]]; then
    aggregate=false
  fi

  argus_cfg_skip_whitespace
  local character="${ARGUS_CFG_PARSE_TEXT:ARGUS_CFG_PARSE_INDEX:1}"
  if [[ "$character" == ")" ]]; then
    ARGUS_CFG_PARSE_INDEX=$((ARGUS_CFG_PARSE_INDEX + 1))
    ARGUS_CFG_PARSE_RESULT="$aggregate"
    return 0
  fi

  while [[ "$ARGUS_CFG_PARSE_VALID" == true ]]; do
    argus_cfg_parse_expression
    if [[ "$ARGUS_CFG_PARSE_VALID" != true ]]; then
      return 0
    fi

    if [[ "$operation" == all && "$ARGUS_CFG_PARSE_RESULT" != true ]]; then
      aggregate=false
    elif [[ "$operation" == any && "$ARGUS_CFG_PARSE_RESULT" == true ]]; then
      aggregate=true
    fi

    argus_cfg_skip_whitespace
    character="${ARGUS_CFG_PARSE_TEXT:ARGUS_CFG_PARSE_INDEX:1}"
    case "$character" in
      ',')
        ARGUS_CFG_PARSE_INDEX=$((ARGUS_CFG_PARSE_INDEX + 1))
        argus_cfg_skip_whitespace
        ;;
      ')')
        ARGUS_CFG_PARSE_INDEX=$((ARGUS_CFG_PARSE_INDEX + 1))
        ARGUS_CFG_PARSE_RESULT="$aggregate"
        return 0
        ;;
      *)
        ARGUS_CFG_PARSE_VALID=false
        ARGUS_CFG_PARSE_RESULT=false
        return 0
        ;;
    esac
  done
}

argus_cfg_parse_expression() {
  argus_cfg_skip_whitespace
  local text_length="${#ARGUS_CFG_PARSE_TEXT}"
  if (( ARGUS_CFG_PARSE_INDEX >= text_length )); then
    ARGUS_CFG_PARSE_VALID=false
    ARGUS_CFG_PARSE_RESULT=false
    return 0
  fi

  local prefix="${ARGUS_CFG_PARSE_TEXT:ARGUS_CFG_PARSE_INDEX:4}"
  if [[ "$prefix" == "all(" ]]; then
    argus_cfg_parse_list all
  elif [[ "$prefix" == "any(" ]]; then
    argus_cfg_parse_list any
  elif [[ "$prefix" == "not(" ]]; then
    ARGUS_CFG_PARSE_INDEX=$((ARGUS_CFG_PARSE_INDEX + 4))
    argus_cfg_parse_expression
    if [[ "$ARGUS_CFG_PARSE_VALID" != true ]]; then
      return 0
    fi
    argus_cfg_skip_whitespace
    if [[ "${ARGUS_CFG_PARSE_TEXT:ARGUS_CFG_PARSE_INDEX:1}" != ")" ]]; then
      ARGUS_CFG_PARSE_VALID=false
      ARGUS_CFG_PARSE_RESULT=false
      return 0
    fi
    ARGUS_CFG_PARSE_INDEX=$((ARGUS_CFG_PARSE_INDEX + 1))
    if [[ "$ARGUS_CFG_PARSE_RESULT" == true ]]; then
      ARGUS_CFG_PARSE_RESULT=false
    else
      ARGUS_CFG_PARSE_RESULT=true
    fi
  else
    argus_cfg_parse_predicate
  fi
}

argus_cfg_expression_matches_target() {
  ARGUS_CFG_PARSE_TEXT="$1"
  ARGUS_CFG_PARSE_INDEX=0
  ARGUS_CFG_PARSE_RESULT=false
  ARGUS_CFG_PARSE_VALID=true

  argus_load_macos_target_cfg_output || return 1
  argus_cfg_parse_expression
  if [[ "$ARGUS_CFG_PARSE_VALID" != true ]]; then
    return 1
  fi

  argus_cfg_skip_whitespace
  if (( ARGUS_CFG_PARSE_INDEX != ${#ARGUS_CFG_PARSE_TEXT} )); then
    return 1
  fi

  [[ "$ARGUS_CFG_PARSE_RESULT" == true ]]
}

# Extract paths from Cargo's top-level include array. This is intentionally a
# small TOML lexer rather than a general parser: Cargo only allows strings or
# inline tables in this key, and target rustflags are inspected separately.
argus_cargo_config_text_includes() {
  awk '
    function scan_value(line, character_position, character) {
      for (character_position = 1; character_position <= length(line); character_position++) {
        character = substr(line, character_position, 1)

        if (value_quote != "") {
          if (value_quote == double_quote && value_escaped) {
            value_path = value_path character
            value_escaped = 0
          } else if (value_quote == double_quote && character == "\\") {
            value_escaped = 1
          } else if (character == value_quote) {
            print value_path
            value_path = ""
            value_quote = ""
          } else {
            value_path = value_path character
          }
          continue
        }

        if (character == single_quote || character == double_quote) {
          value_quote = character
          value_path = ""
        } else if (character == "#") {
          break
        } else if (character == "[") {
          include_array_depth++
        } else if (character == "]") {
          include_array_depth--
        } else if (character == "{") {
          include_table_depth++
        } else if (character == "}") {
          include_table_depth--
        }
      }
    }

    BEGIN {
      single_quote = sprintf("%c", 39)
      double_quote = sprintf("%c", 34)
      in_include = 0
      saw_table = 0
      include_array_depth = 0
      include_table_depth = 0
      value_quote = ""
      value_path = ""
      value_escaped = 0
    }

    {
      line = $0
      if (!in_include) {
        if (line ~ /^[[:space:]]*\[/) {
          saw_table = 1
          next
        }
        if (!saw_table &&
            line ~ /^[[:space:]]*include[[:space:]]*=/) {
          sub(/^[[:space:]]*include[[:space:]]*=[[:space:]]*/, "", line)
          in_include = 1
          scan_value(line)
          if (include_array_depth == 0 && include_table_depth == 0 &&
              value_quote == "") {
            in_include = 0
          }
        }
        next
      }

      scan_value(line)
      if (include_array_depth == 0 && include_table_depth == 0 &&
          value_quote == "") {
        in_include = 0
      }
    }
  '
}

argus_cargo_config_canonical_path() {
  local config_file="$1"
  local config_directory
  local config_basename
  local absolute_directory
  local realpath_config_file

  if [[ "$config_file" == */* ]]; then
    config_directory="${config_file%/*}"
    [[ -n "$config_directory" ]] || config_directory=/
  else
    config_directory="$PWD"
  fi
  config_basename="${config_file##*/}"

  if command -v realpath >/dev/null 2>&1 &&
    realpath_config_file="$(realpath "$config_file" 2>/dev/null)"; then
    printf '%s\n' "$realpath_config_file"
    return 0
  fi

  if ! absolute_directory="$(cd -- "$config_directory" 2>/dev/null && pwd -P)"; then
    return 1
  fi
  printf '%s/%s\n' "$absolute_directory" "$config_basename"
}

# Resolve an include against an explicit Cargo-defined base directory. File
# includes pass the including file's directory; inline CLI includes pass the
# invocation's current working directory.
argus_cargo_config_include_path_from_directory() {
  local base_directory="$1"
  local include_path="$2"

  if [[ "$include_path" == /* ]]; then
    printf '%s\n' "$include_path"
  else
    printf '%s/%s\n' "$base_directory" "$include_path"
  fi
}

argus_cargo_config_text_cfg_target_rustflags() {
  # Print only cfg target expressions whose table or dotted key supplies
  # rustflags. The shell evaluator below decides whether each expression
  # matches the fixed aarch64-apple-darwin product target.
  awk '
    function flush_section() {
      if (section_has_rustflags) {
        print section_expression
      }
    }

    function reset_section() {
      section_expression = ""
      section_has_rustflags = 0
    }

    BEGIN {
      single_quote = sprintf("%c", 39)
      single_prefix = "[target." single_quote "cfg("
      double_prefix = "[target.\"cfg("
      single_dotted_prefix = "target." single_quote "cfg("
      double_dotted_prefix = "target.\"cfg("
      reset_section()
    }

    {
      line = $0
      sub(/^[[:space:]]*/, "", line)

      if (index(line, single_dotted_prefix) == 1) {
        dotted_expression = substr(line, length(single_dotted_prefix) + 1)
        suffix = "\\)[[:space:]]*" single_quote \
          "[[:space:]]*\\.rustflags[[:space:]]*=.*"
        if (dotted_expression ~ suffix) {
          sub(suffix, "", dotted_expression)
          print dotted_expression
        }
        next
      }

      if (index(line, double_dotted_prefix) == 1) {
        dotted_expression = substr(line, length(double_dotted_prefix) + 1)
        suffix = "\\)[[:space:]]*\"[[:space:]]*\\.rustflags" \
          "[[:space:]]*=.*"
        if (dotted_expression ~ suffix) {
          sub(suffix, "", dotted_expression)
          print dotted_expression
        }
        next
      }

      if (index(line, single_prefix) == 1) {
        flush_section()
        section_expression = substr(line, length(single_prefix) + 1)
        suffix = "\\)[[:space:]]*" single_quote "[[:space:]]*\\].*"
        sub(suffix, "", section_expression)
        section_has_rustflags = 0
        next
      }

      if (index(line, double_prefix) == 1) {
        flush_section()
        section_expression = substr(line, length(double_prefix) + 1)
        suffix = "\\)[[:space:]]*\"[[:space:]]*\\].*"
        sub(suffix, "", section_expression)
        section_has_rustflags = 0
        next
      }

      if (line ~ /^\[/) {
        flush_section()
        reset_section()
        next
      }

      if (section_expression != "" &&
          line ~ /^[[:space:]]*rustflags[[:space:]]*=/) {
        section_has_rustflags = 1
      }
    }

    END {
      flush_section()
    }
  '
}

argus_cargo_config_file_has_matching_cfg_target_rustflags() {
  local config_file="$1"
  [[ -f "$config_file" ]] || return 1

  local cfg_expression
  while IFS= read -r cfg_expression; do
    if argus_cfg_expression_matches_target "$cfg_expression"; then
      return 0
    fi
  done < <(argus_cargo_config_text_cfg_target_rustflags <"$config_file")

  return 1
}

argus_cargo_config_value_has_matching_cfg_target_rustflags() {
  local config_value="$1"
  local cfg_expression

  cfg_expression="$(
    awk '
      BEGIN {
        single_quote = sprintf("%c", 39)
        single_prefix = "target." single_quote "cfg("
        double_prefix = "target.\"cfg("
      }
      {
        line = $0
        sub(/^[[:space:]]*/, "", line)
        if (index(line, single_prefix) == 1) {
          cfg_expression = substr(line, length(single_prefix) + 1)
          suffix = "\\)[[:space:]]*" single_quote \
            "[[:space:]]*\\.rustflags[[:space:]]*=[[:space:]]*.*"
          if (cfg_expression ~ suffix) {
            sub(suffix, "", cfg_expression)
            print cfg_expression
            exit
          }
        }
        if (index(line, double_prefix) == 1) {
          cfg_expression = substr(line, length(double_prefix) + 1)
          suffix = "\\)[[:space:]]*\"[[:space:]]*\\.rustflags" \
            "[[:space:]]*=[[:space:]]*.*"
          if (cfg_expression ~ suffix) {
            sub(suffix, "", cfg_expression)
            print cfg_expression
            exit
          }
        }
      }
    ' <<<"$config_value"
  )"

  [[ -n "$cfg_expression" ]] &&
    argus_cfg_expression_matches_target "$cfg_expression"
}

argus_cargo_config_file_has_native_target_rustflags_local() {
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

  if argus_cargo_config_file_has_matching_cfg_target_rustflags "$config_file"; then
    return 0
  fi

  return 1
}

argus_cargo_config_file_has_native_target_rustflags_recursive() {
  local config_file="$1"
  local canonical_config_file
  local visited_file
  local include_path
  local included_config_file
  local config_directory

  [[ -f "$config_file" ]] || return 1
  canonical_config_file="$(argus_cargo_config_canonical_path "$config_file")" ||
    return 1

  for visited_file in "${ARGUS_CARGO_CONFIG_VISITED[@]-}"; do
    if [[ "$visited_file" == "$canonical_config_file" ]]; then
      return 1
    fi
  done
  ARGUS_CARGO_CONFIG_VISITED+=("$canonical_config_file")

  if argus_cargo_config_file_has_native_target_rustflags_local \
    "$canonical_config_file"; then
    return 0
  fi

  # Cargo reports a missing required include while loading the configuration;
  # an absent file cannot contribute a target flag, so leave that validation to
  # Cargo and continue looking for existing optional or required includes.
  config_directory="${canonical_config_file%/*}"
  while IFS= read -r include_path; do
    [[ -n "$include_path" && "$include_path" == *.toml ]] || continue
    included_config_file="$(argus_cargo_config_include_path_from_directory \
      "$config_directory" "$include_path")"
    if [[ -f "$included_config_file" ]] &&
      argus_cargo_config_file_has_native_target_rustflags_recursive \
        "$included_config_file"; then
      return 0
    fi
  done < <(argus_cargo_config_text_includes <"$canonical_config_file")

  return 1
}

argus_cargo_config_file_has_native_target_rustflags() {
  ARGUS_CARGO_CONFIG_VISITED=()
  argus_cargo_config_file_has_native_target_rustflags_recursive "$1"
}

argus_cargo_config_value_has_exact_target_rustflags() {
  local config_value="$1"

  awk '
    BEGIN {
      single_quote = sprintf("%c", 39)
      double_quote = sprintf("%c", 34)
      keys[1] = "target.aarch64-apple-darwin.rustflags"
      keys[2] = "target." double_quote "aarch64-apple-darwin" \
        double_quote ".rustflags"
      keys[3] = "target." single_quote "aarch64-apple-darwin" \
        single_quote ".rustflags"
    }
    {
      line = $0
      sub(/^[[:space:]]*/, "", line)
      for (key_index = 1; key_index <= 3; key_index++) {
        if (index(line, keys[key_index]) == 1) {
          remainder = substr(line, length(keys[key_index]) + 1)
          if (remainder ~ /^[[:space:]]*=[[:space:]]*/) {
            found = 1
            exit
          }
        }
      }
    }
    END { exit(found ? 0 : 1) }
  ' <<<"$config_value"
}

argus_cargo_config_value_has_native_target_rustflags() {
  local config_value="$1"
  local include_path
  local included_config_file

  if argus_cargo_config_value_has_exact_target_rustflags "$config_value" ||
    argus_cargo_config_value_has_matching_cfg_target_rustflags "$config_value"; then
    return 0
  fi

  while IFS= read -r include_path; do
    [[ -n "$include_path" && "$include_path" == *.toml ]] || continue
    included_config_file="$(argus_cargo_config_include_path_from_directory \
      "$PWD" "$include_path")"
    if [[ -f "$included_config_file" ]] &&
      argus_cargo_config_file_has_native_target_rustflags \
        "$included_config_file"; then
      return 0
    fi
  done < <(printf '%s\n' "$config_value" | argus_cargo_config_text_includes)

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

    if argus_cargo_config_value_has_native_target_rustflags "$config_value"; then
      return 0
    fi

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
    # Cargo uses .cargo/config in preference to .cargo/config.toml when both
    # names exist in the same directory.
    if [[ -f "$directory/.cargo/config" ]]; then
      config_file="$directory/.cargo/config"
    elif [[ -f "$directory/.cargo/config.toml" ]]; then
      config_file="$directory/.cargo/config.toml"
    else
      config_file=""
    fi
    if [[ -n "$config_file" ]] &&
      argus_cargo_config_file_has_native_target_rustflags "$config_file"; then
      return 0
    fi

    [[ "$directory" == / ]] && break
    directory="${directory%/*}"
    [[ -n "$directory" ]] || directory=/
  done

  local cargo_home="${CARGO_HOME:-$HOME/.cargo}"
  if [[ -f "$cargo_home/config" ]]; then
    config_file="$cargo_home/config"
  elif [[ -f "$cargo_home/config.toml" ]]; then
    config_file="$cargo_home/config.toml"
  else
    config_file=""
  fi
  if [[ -n "$config_file" ]] &&
    argus_cargo_config_file_has_native_target_rustflags "$config_file"; then
    return 0
  fi

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

argus_environment_variable_is_set() {
  local variable_name="$1"

  if [[ "$variable_name" == *-* ]]; then
    printenv "$variable_name" >/dev/null 2>&1
  else
    declare -p "$variable_name" >/dev/null 2>&1
  fi
}

# cc-rs accepts target-specific variable names containing hyphens, which Bash
# cannot assign directly. Read those names through the process environment and
# let the wrapper carry any updated assignment through env.
argus_environment_variable_value() {
  local variable_name="$1"

  if [[ "$variable_name" == *-* ]]; then
    printenv "$variable_name"
  else
    printf '%s\n' "${!variable_name-}"
  fi
}

argus_append_environment_value() {
  local variable_name="$1"
  local value="$2"
  local marker="$3"
  local existing_value

  existing_value="$(argus_environment_variable_value "$variable_name")"
  if [[ "$existing_value" == *"$marker"* ]]; then
    return 0
  fi

  if [[ -n "$existing_value" ]]; then
    existing_value+=" "
  fi
  existing_value+="$value"

  if [[ "$variable_name" == *-* ]]; then
    # Bash cannot declare a hyphenated variable. The wrapper passes this
    # assignment to Cargo through env after the policy has been evaluated.
    ARGUS_MACOS_ENV_ASSIGNMENTS+=("$variable_name=$existing_value")
    return 0
  fi

  printf -v "$variable_name" '%s' "$existing_value"
  export "${variable_name?}"
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
  local marker="$ARGUS_MACOS_DEPLOYMENT_TARGET_CFLAGS_PREFIX$fingerprint"
  local variable_name

  for variable_name in \
    CFLAGS_aarch64-apple-darwin \
    CFLAGS_aarch64_apple_darwin \
    TARGET_CFLAGS \
    CFLAGS; do
    if argus_environment_variable_is_set "$variable_name"; then
      argus_append_environment_value "$variable_name" "$marker" "$marker"
      return 0
    fi
  done

  argus_append_environment_value CFLAGS "$marker" "$marker"
}

# Configure the environment shared by the Rust compiler and native C build
# scripts. The host parameters are explicit so the contract can be tested on
# a non-macOS machine without pretending that its uname output is different.
argus_configure_macos_rust_build_environment() {
  local host_os="$1"
  local host_arch="$2"
  shift 2
  ARGUS_MACOS_ENV_ASSIGNMENTS=()

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

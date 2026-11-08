#!/usr/bin/env bash
set -euo pipefail

# Each CSV path is relative to flutter/. Validate all paths before invoking FVM.
if [[ "$#" -lt 1 || "$#" -gt 2 || -z "$1" ]]; then
  echo 'Usage: run_flutter_focused.sh test/path.dart[,test/path2.dart] [lib/path.dart[,test/path3.dart]]' >&2
  exit 64
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
if [[ -L "$repo_root/flutter" ]]; then
  echo 'Symlinked Flutter root' >&2
  exit 64
fi
flutter_root="$(cd "$repo_root/flutter" && pwd -P)"

split_paths() {
  local csv="$1"
  local kind="$2"
  local path
  if [[ -z "$csv" ]]; then
    return
  fi
  # Bash 'read' stops at the first newline. Reject line breaks before parsing
  # so an otherwise valid first path cannot silently hide a trailing argument.
  if [[ "$csv" == *$'\n'* || "$csv" == *$'\r'* ]]; then
    echo "Invalid ${kind} path list (line break)" >&2
    exit 64
  fi
  if [[ ! "$csv" =~ ^[^,]+(,[^,]+)*$ ]]; then
    echo "Invalid ${kind} path list" >&2
    exit 64
  fi
  local -a entries=()
  IFS=',' read -r -a entries <<< "$csv"
  for path in "${entries[@]}"; do
    if [[ "$kind" == tests ]]; then
      if [[ ! "$path" =~ ^test/([A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+\.dart$ ]]; then
        echo "Invalid test path: $path" >&2
        exit 64
      fi
      test_paths+=("$path")
    else
      if [[ ! "$path" =~ ^(test|lib)/([A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+\.dart$ ]]; then
        echo "Invalid format path: $path" >&2
        exit 64
      fi
      format_paths+=("$path")
    fi
    # Checking only the final file misses a symlinked directory ancestor.
    # Reject every symlink component before invoking either formatter or tests.
    local current="$flutter_root"
    local component
    local -a components=()
    IFS='/' read -r -a components <<< "$path"
    for component in "${components[@]}"; do
      current="$current/$component"
      if [[ -L "$current" ]]; then
        echo "Symlinked Flutter path: $path" >&2
        exit 64
      fi
    done
    if [[ ! -f "$flutter_root/$path" || -L "$flutter_root/$path" ]]; then
      echo "Missing or symlinked Flutter file: $path" >&2
      exit 64
    fi
  done
}

test_paths=()
format_paths=()
split_paths "$1" tests
format_paths=("${test_paths[@]}")
split_paths "${2:-}" format

(
  cd "$flutter_root"
  fvm dart format --output=none --set-exit-if-changed "${format_paths[@]}"
  fvm flutter test --no-pub "${test_paths[@]}"
)

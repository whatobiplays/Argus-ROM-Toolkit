#!/usr/bin/env bash
# Build only task-owned native artifacts; never sign, install, enroll, or use sudo.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
native_root="$repo_root/native/fixture-staging"
build_root="$repo_root/.build/fixture-staging"
mode="${1:-test}"
case "$mode" in
  build|test|analyze|contract|store|security|service|broker|proof|timing|sanitize|reproducibility) ;;
  *) printf '%s\n' 'Usage: build_fixture_staging_native.sh [build|test|analyze|contract|store|security|service|broker|proof|timing|sanitize|reproducibility]' >&2; exit 2 ;;
esac
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  printf '%s\n' 'BLOCKED_UNSUPPORTED_NATIVE_BUILD_PLATFORM' >&2
  exit 2
fi
cd -- "$repo_root"
capacity() {
  PYTHONDONTWRITEBYTECODE=1 python3 -m scripts.android_qualification.staging_resources "$build_root"
}
capacity
mkdir -p -- "$build_root/objects" "$build_root/tmp"

# Eliminate caller-controlled compiler, loader, SDK and library-search settings.
# No modules or DerivedData cache is necessary for the small Objective-C targets.
compiler=(/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C
  TMPDIR="$build_root/tmp/" /usr/bin/xcrun --sdk macosx clang)
dsymutil=(/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C
  TMPDIR="$build_root/tmp/" /usr/bin/xcrun --sdk macosx dsymutil)

# Hash every native input by relative path, mode, and content so both
# reproducibility builds can prove that they consumed the same frozen inputs.
native_input_manifest_sha256() {
  PYTHONDONTWRITEBYTECODE=1 python3 - "$native_root" <<'PY'
from hashlib import sha256
from pathlib import Path
import stat
import sys

root = Path(sys.argv[1])
manifest = sha256()
for path in sorted(item for item in root.rglob("*") if item.is_file()):
    relative_path = path.relative_to(root).as_posix().encode("utf-8")
    mode = f"{stat.S_IMODE(path.stat().st_mode):04o}".encode("ascii")
    content_digest = sha256(path.read_bytes()).hexdigest().encode("ascii")
    manifest.update(relative_path + b"\0" + mode + b"\0" + content_digest + b"\n")
print(manifest.hexdigest())
PY
}

repro_artifact_names=(
  binary-service binary-broker binary-proof-driver binary-proof-actor
  dwarf-service dwarf-broker dwarf-proof-driver dwarf-proof-actor
)
repro_artifacts=(
  "$build_root/argus-staging-service"
  "$build_root/ArgusStagingBroker.app/Contents/MacOS/ArgusStagingBroker"
  "$build_root/argus-proof-driver"
  "$build_root/argus-proof-actor"
  "$build_root/argus-staging-service.dSYM/Contents/Resources/DWARF/argus-staging-service"
  "$build_root/ArgusStagingBroker.app/Contents/MacOS/ArgusStagingBroker.dSYM/Contents/Resources/DWARF/ArgusStagingBroker"
  "$build_root/argus-proof-driver.dSYM/Contents/Resources/DWARF/argus-proof-driver"
  "$build_root/argus-proof-actor.dSYM/Contents/Resources/DWARF/argus-proof-actor"
)
captured_artifact_hashes=()
# Record the executable and matching DWARF payload hashes from one build pass.
capture_repro_artifact_hashes() {
  local pass="$1"
  local index artifact digest
  captured_artifact_hashes=()
  for index in "${!repro_artifacts[@]}"; do
    artifact="${repro_artifacts[$index]}"
    if [[ ! -f "$artifact" ]]; then
      printf '%s\n' "NATIVE_REPRODUCIBILITY_ARTIFACT_MISSING: $artifact" >&2
      exit 1
    fi
    digest="$(/usr/bin/shasum -a 256 "$artifact")"
    digest="${digest%% *}"
    captured_artifact_hashes+=("$digest")
    printf 'NATIVE_REPRODUCIBILITY_%s_%s_SHA256=%s\n' \
      "$pass" "${repro_artifact_names[$index]}" "$digest"
  done
}

# Verify the native input manifest before and after one complete production build.
run_reproducibility_build() {
  local pass="$1"
  local expected_manifest="$2"
  local actual_manifest
  actual_manifest="$(native_input_manifest_sha256)"
  if [[ "$actual_manifest" != "$expected_manifest" ]]; then
    printf 'NATIVE_INPUT_MANIFEST_CHANGED_BEFORE_BUILD_%s: expected=%s actual=%s\n' \
      "$pass" "$expected_manifest" "$actual_manifest" >&2
    exit 1
  fi
  printf 'NATIVE_INPUT_MANIFEST_BEFORE_BUILD_%s=%s\n' "$pass" "$actual_manifest"
  printf 'NATIVE_REPRODUCIBILITY_BUILD=%s\n' "$pass"
  AQ_NATIVE_SANITIZERS=0 bash "$repo_root/scripts/build_fixture_staging_native.sh" build
  actual_manifest="$(native_input_manifest_sha256)"
  if [[ "$actual_manifest" != "$expected_manifest" ]]; then
    printf 'NATIVE_INPUT_MANIFEST_CHANGED_AFTER_BUILD_%s: expected=%s actual=%s\n' \
      "$pass" "$expected_manifest" "$actual_manifest" >&2
    exit 1
  fi
  printf 'NATIVE_INPUT_MANIFEST_AFTER_BUILD_%s=%s\n' "$pass" "$actual_manifest"
}

# Compare two serial builds against the same native input manifest.
run_reproducibility_check() {
  local expected_manifest index
  local -a first_hashes=()
  expected_manifest="$(native_input_manifest_sha256)"
  printf 'NATIVE_INPUT_MANIFEST_SHA256=%s\n' "$expected_manifest"

  run_reproducibility_build 1 "$expected_manifest"
  capture_repro_artifact_hashes 1
  first_hashes=("${captured_artifact_hashes[@]}")

  run_reproducibility_build 2 "$expected_manifest"
  capture_repro_artifact_hashes 2
  for index in "${!first_hashes[@]}"; do
    if [[ "${first_hashes[$index]}" != "${captured_artifact_hashes[$index]}" ]]; then
      printf 'NATIVE_REPRODUCIBILITY_MISMATCH: %s first=%s second=%s\n' \
        "${repro_artifact_names[$index]}" \
        "${first_hashes[$index]}" "${captured_artifact_hashes[$index]}" >&2
      exit 1
    fi
  done
  printf 'NATIVE_REPRODUCIBILITY=PASS artifacts=%s\n' "${#repro_artifacts[@]}"
}

# Keep the two-build check opt-in so the default test mode remains a single pass.
if [[ "$mode" == reproducibility ]]; then
  run_reproducibility_check
  exit 0
fi

if [[ "$mode" == test ]]; then
  for suite in contract store security timing service broker proof; do
    bash "$repo_root/scripts/build_fixture_staging_native.sh" "$suite"
  done
  exit 0
fi
if [[ "$mode" == sanitize ]]; then
  AQ_NATIVE_SANITIZERS=1 bash "$repo_root/scripts/build_fixture_staging_native.sh" test
  exit 0
fi
flags=(-fno-modules -arch arm64 -mmacosx-version-min=12.0 -Wall -Wextra -Werror \
 -Wnullable-to-nonnull-conversion
 -I "$native_root/core" -I "$native_root/service" -I "$native_root/broker"
 -g "-ffile-prefix-map=$repo_root=.")
if [[ "${AQ_NATIVE_SANITIZERS:-0}" == 1 ]]; then
  flags+=('-fsanitize=address,undefined' -fno-omit-frame-pointer -O1)
fi
if [[ "$mode" == store ]]; then
  flags+=(-DAQ_STORE_TESTING)
fi
if [[ "$mode" == security ]]; then
  flags+=(-DAQ_SECURITY_TESTING)
fi
frameworks=(-framework Foundation -framework Security -framework AppKit -framework LocalAuthentication)
objects=()
shopt -s nullglob
if [[ "$mode" == contract ]]; then
  sources=("$native_root/core/AQJSON.m" "$native_root/core/AQContract.m")
elif [[ "$mode" == store ]]; then
  sources=("$native_root/core/AQJSON.m" "$native_root/core/AQStore.m")
elif [[ "$mode" == security ]]; then
  sources=("$native_root/core/AQJSON.m" "$native_root/core/AQSecurity.m")
elif [[ "$mode" == timing ]]; then
  sources=("$native_root/core/AQTiming.m")
elif [[ "$mode" == service ]]; then
  sources=("$native_root"/core/*.m "$native_root/service/AQServiceProtocol.m" \
    "$native_root/service/AQServiceReceiptJournal.m")
elif [[ "$mode" == broker ]]; then
  sources=("$native_root"/core/*.m "$native_root/service/AQServiceProtocol.m" \
    "$native_root/service/AQServiceReceiptJournal.m" "$native_root/broker/AQBrokerProtocol.m")
else
  sources=("$native_root"/core/*.c "$native_root"/core/*.m \
    "$native_root/service/AQServiceProtocol.m" \
    "$native_root/service/AQServiceReceiptJournal.m" "$native_root/broker/AQBrokerProtocol.m")
fi
if (( ${#sources[@]} == 0 )); then
  printf '%s\n' 'NATIVE_SOURCE_INCOMPLETE' >&2
  exit 2
fi
for source in "${sources[@]}"; do
  capacity
  object="$build_root/objects/${mode}-$(basename "$source").o"
  language_flags=()
  [[ "$source" != *.m ]] || language_flags=(-fobjc-arc)
  if [[ "$mode" == analyze ]]; then
    "${compiler[@]}" "${flags[@]}" "${language_flags[@]}" --analyze "$source" -o "$object.plist"
  else
    "${compiler[@]}" "${flags[@]}" "${language_flags[@]}" -c "$source" -o "$object"
    objects+=("$object")
  fi
done
[[ "$mode" != analyze ]] || exit 0

production_main_objects=()
production_service_object="$build_root/objects/production-service-main.o"
production_broker_object="$build_root/objects/production-broker-main.o"
production_proof_driver_object="$build_root/objects/production-proof-driver.o"
production_proof_actor_object="$build_root/objects/production-proof-actor.o"
# Give each production entry point a stable object path for reproducible linking.
compile_production_main_object() {
  local object="$1"
  local source="$2"
  capacity
  "${compiler[@]}" "${flags[@]}" -fobjc-arc -c "$source" -o "$object"
  production_main_objects+=("$object")
}
case "$mode" in
  build)
    compile_production_main_object "$production_service_object" "$native_root/service/main.m"
    compile_production_main_object "$production_broker_object" "$native_root/broker/main.m"
    compile_production_main_object "$production_proof_driver_object" "$native_root/proof/driver.m"
    compile_production_main_object "$production_proof_actor_object" "$native_root/proof/actor.m"
    ;;
  service)
    compile_production_main_object "$production_service_object" "$native_root/service/main.m"
    ;;
  broker)
    compile_production_main_object "$production_broker_object" "$native_root/broker/main.m"
    ;;
  proof)
    compile_production_main_object "$production_proof_driver_object" "$native_root/proof/driver.m"
    compile_production_main_object "$production_proof_actor_object" "$native_root/proof/actor.m"
    ;;
esac

assert_no_test_symbols() {
  local object symbols
  for object in "${objects[@]}" "${production_main_objects[@]}"; do
    symbols="$(/usr/bin/nm -gU "$object")"
    if [[ "$symbols" =~ AQ[A-Za-z0-9_]*Test ]]; then
      printf '%s\n' "NATIVE_PRODUCTION_TEST_SYMBOL_PRESENT: $object" >&2
      exit 1
    fi
  done
  printf '%s\n' 'NATIVE_PRODUCTION_TEST_SYMBOLS=ABSENT'
}

assert_production_binary_has_no_test_symbols() {
  local binary="$1"
  local symbols
  symbols="$(/usr/bin/nm -gU "$binary")"
  if [[ "$symbols" =~ AQ[A-Za-z0-9_]*Test ]]; then
    printf '%s\n' "NATIVE_PRODUCTION_BINARY_TEST_SYMBOL_PRESENT: $binary" >&2
    exit 1
  fi
  printf '%s\n' 'NATIVE_PRODUCTION_BINARY_TEST_SYMBOLS=ABSENT'
}

assert_service_clock_domains() {
  local binary="$1"
  local symbols
  symbols="$(/usr/bin/nm -u "$binary")"
  if ! /usr/bin/grep -qx '_mach_continuous_time' <<<"$symbols"; then
    printf '%s\n' "NATIVE_STORE_CONTINUOUS_CLOCK_MISSING: $binary" >&2
    exit 1
  fi
  if ! /usr/bin/grep -qx '_mach_absolute_time' <<<"$symbols"; then
    printf '%s\n' "NATIVE_SERVICE_ABSOLUTE_CLOCK_MISSING: $binary" >&2
    exit 1
  fi
  printf '%s\n' 'NATIVE_SERVICE_CLOCK_DOMAINS=ABSOLUTE_AND_CONTINUOUS'
}

if [[ "$mode" == build || "$mode" == service || "$mode" == broker || "$mode" == proof ]]; then
  assert_no_test_symbols
fi

link_target() {
  local output="$1"
  shift
  capacity
  "${compiler[@]}" "${flags[@]}" -fobjc-arc "$@" "${objects[@]}" "${frameworks[@]}" -o "$output"
}

# Link a production binary from named objects and emit a same-basename dSYM.
link_production_target() {
  local output="$1"
  local main_object="$2"
  local dwarf_bundle="${output}.dSYM"
  capacity
  "${compiler[@]}" "${flags[@]}" -fobjc-arc "$main_object" \
    "${objects[@]}" "${frameworks[@]}" -Wl,-reproducible -o "$output"
  capacity
  # Replace only this script-owned bundle so repeated builds start from a clean dSYM output.
  /bin/rm -rf -- "$dwarf_bundle"
  "${dsymutil[@]}" "$output" -o "$dwarf_bundle"
}

if [[ "$mode" == security ]]; then
  link_target "$build_root/security-tests" -DAQ_SECURITY_TEST_MAIN \
    "$native_root/tests/security_tests.m"
  "$build_root/security-tests"
  exit 0
fi

if [[ "$mode" == contract ]]; then
  link_target "$build_root/contract-tests" -DAQ_CONTRACT_TEST_MAIN \
    "$native_root/tests/contract_tests.m"
  "$build_root/contract-tests" "$native_root/fixtures"
  exit 0
fi

if [[ "$mode" == store ]]; then
  link_target "$build_root/store-tests" -DAQ_STORE_TESTING -DAQ_STORE_STANDALONE \
    "$native_root/tests/store_tests.m"
  "$build_root/store-tests"
  exit 0
fi

run_blocked_proof_checks() {
  local output status
  set +e
  output=$("$build_root/argus-proof-driver" --self-check 2>&1)
  status=$?
  set -e
  [[ $status -eq 2 && "$output" == *BLOCKED* ]] || {
    printf '%s\n' 'PROOF_DRIVER_FAIL_CLOSED_CHECK_FAILED' >&2
    exit 1
  }
  set +e
  output=$("$build_root/argus-proof-actor" --self-check 2>&1)
  status=$?
  set -e
  [[ $status -eq 2 && "$output" == *BLOCKED* ]] || {
    printf '%s\n' 'PROOF_ACTOR_FAIL_CLOSED_CHECK_FAILED' >&2
    exit 1
  }
}

if [[ "$mode" == service ]]; then
  link_production_target "$build_root/argus-staging-service" "$production_service_object"
  assert_production_binary_has_no_test_symbols "$build_root/argus-staging-service"
  assert_service_clock_domains "$build_root/argus-staging-service"

  # Exercise the native boundary with production service objects and no
  # synthetic-test override compiled into the implementation.
  link_target "$build_root/service-production-boundary-tests" \
    -DAQ_SERVICE_TEST_MAIN -DAQ_SERVICE_TESTING \
    -DAQ_SERVICE_PRODUCTION_BOUNDARY_TEST_MAIN \
    "$native_root/service/main.m" \
    "$native_root/tests/service_tests.m"
  "$build_root/service-production-boundary-tests"

  # Compile only the protocol implementation with test hooks for the synthetic
  # service suite; keep the other production objects unchanged.
  service_test_objects=()
  for object in "${objects[@]}"; do
    if [[ "$object" == "$build_root/objects/service-AQServiceProtocol.m.o" ]]; then
      capacity
      test_protocol_object="$build_root/objects/service-testing-AQServiceProtocol.m.o"
      "${compiler[@]}" "${flags[@]}" -DAQ_SERVICE_TESTING -fobjc-arc \
        -c "$native_root/service/AQServiceProtocol.m" -o "$test_protocol_object"
      service_test_objects+=("$test_protocol_object")
    else
      service_test_objects+=("$object")
    fi
  done
  objects=("${service_test_objects[@]}")
  link_target "$build_root/service-tests" -DAQ_SERVICE_TEST_MAIN -DAQ_SERVICE_TESTING \
    "$native_root/service/main.m" \
    "$native_root/tests/service_tests.m"
  "$build_root/service-tests"
  exit 0
fi

if [[ "$mode" == broker ]]; then
  mkdir -p -- "$build_root/ArgusStagingBroker.app/Contents/MacOS"
  link_production_target \
    "$build_root/ArgusStagingBroker.app/Contents/MacOS/ArgusStagingBroker" \
    "$production_broker_object"
  assert_production_binary_has_no_test_symbols \
    "$build_root/ArgusStagingBroker.app/Contents/MacOS/ArgusStagingBroker"
  cp -- "$native_root/broker/Info.plist" "$build_root/ArgusStagingBroker.app/Contents/Info.plist"
  broker_test_objects=()
  for source in "${sources[@]}"; do
    capacity
    object="$build_root/objects/broker-test-$(basename "$source").o"
    language_flags=()
    [[ "$source" != *.m ]] || language_flags=(-fobjc-arc)
    "${compiler[@]}" "${flags[@]}" -DAQ_BROKER_TESTING "${language_flags[@]}" \
      -c "$source" -o "$object"
    broker_test_objects+=("$object")
  done
  capacity
  "${compiler[@]}" "${flags[@]}" -fobjc-arc -DAQ_BROKER_TESTING \
    -DAQ_BROKER_TEST_MAIN \
    "$native_root/tests/broker_tests.m" \
    "${broker_test_objects[@]}" "${frameworks[@]}" -o "$build_root/broker-tests"
  "$build_root/broker-tests"
  exit 0
fi

if [[ "$mode" == proof ]]; then
  link_production_target "$build_root/argus-proof-driver" "$production_proof_driver_object"
  link_production_target "$build_root/argus-proof-actor" "$production_proof_actor_object"
  run_blocked_proof_checks
  exit 0
fi

if [[ "$mode" == timing ]]; then
  link_target "$build_root/timing-tests" -DAQ_TIMING_STANDALONE \
    "$native_root/tests/timing_tests.m"
  assert_service_clock_domains "$build_root/timing-tests"
  "$build_root/timing-tests"
  exit 0
fi

if [[ "$mode" == build ]]; then
  link_production_target "$build_root/argus-staging-service" "$production_service_object"
  assert_production_binary_has_no_test_symbols "$build_root/argus-staging-service"
  assert_service_clock_domains "$build_root/argus-staging-service"
  mkdir -p -- "$build_root/ArgusStagingBroker.app/Contents/MacOS"
  link_production_target \
    "$build_root/ArgusStagingBroker.app/Contents/MacOS/ArgusStagingBroker" \
    "$production_broker_object"
  assert_production_binary_has_no_test_symbols \
    "$build_root/ArgusStagingBroker.app/Contents/MacOS/ArgusStagingBroker"
  cp -- "$native_root/broker/Info.plist" "$build_root/ArgusStagingBroker.app/Contents/Info.plist"
  link_production_target "$build_root/argus-proof-driver" "$production_proof_driver_object"
  link_production_target "$build_root/argus-proof-actor" "$production_proof_actor_object"
  exit 0
fi

link_production_target "$build_root/argus-staging-service" "$production_service_object"
assert_production_binary_has_no_test_symbols "$build_root/argus-staging-service"
mkdir -p -- "$build_root/ArgusStagingBroker.app/Contents/MacOS"
link_production_target \
  "$build_root/ArgusStagingBroker.app/Contents/MacOS/ArgusStagingBroker" \
  "$production_broker_object"
assert_production_binary_has_no_test_symbols \
  "$build_root/ArgusStagingBroker.app/Contents/MacOS/ArgusStagingBroker"
cp -- "$native_root/broker/Info.plist" "$build_root/ArgusStagingBroker.app/Contents/Info.plist"
link_production_target "$build_root/argus-proof-driver" "$production_proof_driver_object"
link_production_target "$build_root/argus-proof-actor" "$production_proof_actor_object"

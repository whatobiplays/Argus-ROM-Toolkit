#!/usr/bin/env bash
set -euo pipefail

# Shared setup for focused Phase 002 Android scenarios. Each scenario remains
# a separate command and owns only its device fixture and evidence paths.

# Returns records present in the current bounded command output but absent
# from the baseline output. Both arguments are newline-delimited records.
argus_android_records_added() {
  local baseline="$1"
  local current="$2"
  comm -13 \
    <(printf '%s\n' "${baseline}" | awk 'NF' | sort) \
    <(printf '%s\n' "${current}" | awk 'NF' | sort)
}

# Normalizes one `sm list-volumes public` record to its stable first three
# fields: vold volume id, state, and provider/native volume identity.
argus_android_parse_public_volume_record() {
  local record="$1"
  awk 'NF >= 3 { print $1, $2, $3; exit }' <<<"${record}"
}

# Extracts the public volume's adoptable disk id and transient /storage path
# from `dumpsys mount`, but only when the backing disk advertises the SD flag.
# The SD flag is the bounded native indication that the public volume is
# removable; StorageManager remains the authority used by the integration test.
argus_android_parse_public_volume_mount_info() {
  local volume_id="$1"
  local mount_dump="$2"
  awk -v wanted_volume="${volume_id}" '
    /^  DiskInfo\{/ {
      disk_id = $0
      sub(/^  DiskInfo\{/, "", disk_id)
      sub(/\}:$/, "", disk_id)
      in_disk = 1
      next
    }
    in_disk && /^    flags=/ {
      flags = $0
      sub(/^    flags=/, "", flags)
      sub(/ .*/, "", flags)
      disk_flags[disk_id] = flags
      in_disk = 0
      next
    }
    $0 == "  VolumeInfo{" wanted_volume "}:" {
      in_volume = 1
      next
    }
    in_volume && /^  VolumeInfo\{/ { exit }
    in_volume && /type=PUBLIC/ {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^diskId=/) {
          volume_disk = $i
          sub(/^diskId=/, "", volume_disk)
        }
      }
      next
    }
    in_volume && /path=\/storage\// {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^path=\/storage\//) {
          mount_path = $i
          sub(/^path=/, "", mount_path)
        }
      }
      if (disk_flags[volume_disk] ~ /(^|\|)(SD|USB)(\||$)/) {
        print volume_disk, mount_path
      }
      exit
    }
  ' <<<"${mount_dump}"
}

# Returns success only when every requested command is present in the actual
# `sm help` output. API level alone is not sufficient to authorize mutation.
argus_android_sm_help_supports_commands() {
  local sm_help="$1"
  shift
  local command
  for command in "$@"; do
    if ! grep -Eq "(^|[[:space:]])${command}([[:space:]]|$)" <<<"${sm_help}"; then
      return 1
    fi
  done
}

argus_android_require_device() {
  local require_arm64="${ARGUS_ANDROID_DEVICE_REQUIRE_ARM64:-true}"
  if [[ "${require_arm64}" != true && "${require_arm64}" != false ]]; then
    printf 'ARGUS_ANDROID_DEVICE_REQUIRE_ARM64 must be true or false\n' >&2
    return 1
  fi
  ARGUS_ANDROID_SCENARIO_ADB="${ARGUS_ANDROID_ADB:-$(command -v adb || true)}"
  if [[ -z "${ARGUS_ANDROID_SCENARIO_ADB}" ||
    ! -x "${ARGUS_ANDROID_SCENARIO_ADB}" ]]; then
    printf 'Required developer tool is missing: adb\n' >&2
    return 1
  fi
  command -v fvm >/dev/null 2>&1 || {
    printf 'Required developer tool is missing: fvm\n' >&2
    return 1
  }

  ARGUS_ANDROID_SCENARIO_DEVICE="${ARGUS_ANDROID_DEVICE_ID:-}"
  if [[ -z "${ARGUS_ANDROID_SCENARIO_DEVICE}" ]]; then
    local devices
    devices="$(${ARGUS_ANDROID_SCENARIO_ADB} devices |
      awk 'NR > 1 && $2 == "device" { print $1 }')"
    if [[ -z "${devices}" ]]; then
      printf 'No connected Android device found\n' >&2
      return 1
    fi
    if [[ "${devices}" == *$'\n'* ]]; then
      printf 'Exactly one connected Android device is required or set ARGUS_ANDROID_DEVICE_ID\n' >&2
      return 1
    fi
    ARGUS_ANDROID_SCENARIO_DEVICE="${devices}"
  fi

  local state
  state="$(${ARGUS_ANDROID_SCENARIO_ADB} -s \
    "${ARGUS_ANDROID_SCENARIO_DEVICE}" get-state 2>/dev/null | tr -d '\r')"
  if [[ "${state}" != device ]]; then
    printf 'Selected Android device is not online: %s\n' "${state}" >&2
    return 1
  fi

  ARGUS_ANDROID_SCENARIO_API="$(${ARGUS_ANDROID_SCENARIO_ADB} -s \
    "${ARGUS_ANDROID_SCENARIO_DEVICE}" shell getprop ro.build.version.sdk |
    tr -d '\r')"
  if [[ "${ARGUS_ANDROID_SCENARIO_API}" != 36 ]]; then
    printf 'P02-005 native scenarios require API 36; device reports %s\n' \
      "${ARGUS_ANDROID_SCENARIO_API}" >&2
    return 1
  fi
  local abi
  abi="$(${ARGUS_ANDROID_SCENARIO_ADB} -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
    shell getprop ro.product.cpu.abi | tr -d '\r')"
  export ARGUS_ANDROID_SCENARIO_ABI="${abi}"
  if [[ "${require_arm64}" == true && "${abi}" != arm64-v8a ]]; then
    printf 'P02-005 native scenarios require ARM64; device reports %s\n' \
      "${abi}" >&2
    return 1
  fi
  # P02-006 records the actual emulator ABI and accepts either ABI packaged by
  # the repository APK. Earlier P02-005 scenarios retain their ARM64 gate.
  if [[ "${require_arm64}" == false &&
    "${abi}" != arm64-v8a && "${abi}" != x86_64 ]]; then
    printf 'P02-006 native scenarios require a packaged ABI (arm64-v8a or x86_64); device reports %s\n' \
      "${abi}" >&2
    return 1
  fi
}

argus_android_build_and_install() {
  local root_dir="$1"
  local package_id="dev.argusromtoolkit.argus"
  (
    cd "${root_dir}/flutter"
    fvm flutter build apk --debug --target-platform android-arm64,android-x64
  )
  local apk_path="${root_dir}/flutter/build/app/outputs/flutter-apk/app-debug.apk"
  if [[ ! -f "${apk_path}" ]]; then
    printf 'Expected debug APK was not produced: %s\n' "${apk_path}" >&2
    return 1
  fi
  "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
    install -r "${apk_path}" >/dev/null
  "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
    shell pm clear "${package_id}" >/dev/null
  "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
    shell appops set --uid "${package_id}" MANAGE_EXTERNAL_STORAGE allow
  if (( ARGUS_ANDROID_SCENARIO_API >= 33 )); then
    "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
      shell pm grant "${package_id}" android.permission.POST_NOTIFICATIONS || true
  fi
}

argus_android_run_integration() {
  local root_dir="$1"
  local test_file="$2"
  shift 2
  (
    cd "${root_dir}/flutter"
    fvm flutter test "integration_test/${test_file}" "$@" \
      --no-uninstall -d "${ARGUS_ANDROID_SCENARIO_DEVICE}"
  )
}

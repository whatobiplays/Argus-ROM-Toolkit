#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE_ROOT="/sdcard/ArgusP02005Evidence"
EVIDENCE_PATH="${EVIDENCE_ROOT}/removable-root-id.txt"
PACKAGE_ID="com.argusromtoolkit.argus"
POLL_SECONDS="${ARGUS_ANDROID_REMOVABLE_POLL_SECONDS:-30}"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/run_phase_002_android_scenario_common.sh"
argus_android_require_device

if ! [[ "${POLL_SECONDS}" =~ ^[1-9][0-9]*$ ]]; then
  printf 'Invalid ARGUS_ANDROID_REMOVABLE_POLL_SECONDS: %s\n' \
    "${POLL_SECONDS}" >&2
  exit 1
fi

ADB="${ARGUS_ANDROID_SCENARIO_ADB}"
DEVICE="${ARGUS_ANDROID_SCENARIO_DEVICE}"

sm_output() {
  "${ADB}" -s "${DEVICE}" shell sm "$@" | tr -d '\r'
}

public_volumes() {
  sm_output list-volumes public
}

adoptable_disks() {
  sm_output list-disks adoptable
}

mount_dump() {
  "${ADB}" -s "${DEVICE}" shell dumpsys mount | tr -d '\r'
}

normalize_provider_id() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

volume_record_for_state() {
  local volume_id="$1"
  local expected_state="$2"
  public_volumes | awk -v id="${volume_id}" -v state="${expected_state}" \
    '$1 == id && $2 == state { print; exit }'
}

mounted_public_records() {
  public_volumes | awk \
    '$1 ~ /^public:/ && $2 == "mounted" && $3 != "" { print }'
}

record_count() {
  awk 'NF { count++ } END { print count + 0 }' <<<"$1"
}

wait_for_new_adoptable_disk() {
  local current
  local added
  local count
  for ((attempt = 1; attempt <= POLL_SECONDS; attempt++)); do
    current="$(adoptable_disks)"
    added="$(argus_android_records_added "${BASELINE_ADOPTABLE_DISKS}" "${current}")"
    count="$(record_count "${added}")"
    if [[ "${count}" -eq 1 ]]; then
      printf '%s\n' "${added}"
      return 0
    fi
    if [[ "${count}" -gt 1 ]]; then
      return 2
    fi
    sleep 1
  done
  return 1
}

wait_for_new_public_volume_record() {
  local current
  local added
  local count
  for ((attempt = 1; attempt <= POLL_SECONDS; attempt++)); do
    current="$(public_volumes)"
    added="$(argus_android_records_added "${BASELINE_PUBLIC_VOLUMES}" "${current}")"
    count="$(record_count "${added}")"
    if [[ "${count}" -eq 1 ]]; then
      printf '%s\n' "${added}"
      return 0
    fi
    if [[ "${count}" -gt 1 ]]; then
      return 2
    fi
    sleep 1
  done
  return 1
}

wait_for_volume_state() {
  local volume_id="$1"
  local expected_state="$2"
  local record
  for ((attempt = 1; attempt <= POLL_SECONDS; attempt++)); do
    record="$(volume_record_for_state "${volume_id}" "${expected_state}")"
    if [[ -n "${record}" ]]; then
      printf '%s\n' "${record}"
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_removable_mount_info() {
  local volume_id="$1"
  local current_dump
  local metadata
  for ((attempt = 1; attempt <= POLL_SECONDS; attempt++)); do
    current_dump="$(mount_dump)"
    metadata="$(argus_android_parse_public_volume_mount_info \
      "${volume_id}" "${current_dump}")"
    if [[ -n "${metadata}" ]]; then
      printf '%s\n' "${metadata}"
      return 0
    fi
    sleep 1
  done
  return 1
}

unverified() {
  printf 'UNVERIFIED: %s\n' "$*" >&2
  exit 2
}

BASELINE_PUBLIC_VOLUMES="$(public_volumes)"
BASELINE_ADOPTABLE_DISKS="$(adoptable_disks)"
BASELINE_MOUNT_DUMP="$(mount_dump)"
BASELINE_MOUNTED_PUBLIC_RECORDS="$(mounted_public_records)"

volume_id=""
provider_id=""
mount_path=""
disk_id=""
provisioned_virtual_disk=false
virtual_disk_enable_attempted=false
virtual_disk_cleanup_allowed=false

# A blank adoptable-disk baseline is the conservative ownership boundary for
# undoing a virtual-disk enable attempt. Pre-existing disks are never removed.
if [[ -z "${BASELINE_ADOPTABLE_DISKS}" ]]; then
  virtual_disk_cleanup_allowed=true
fi

cleanup() {
  local mounted_state
  set +e

  if [[ -n "${volume_id}" ]]; then
    mounted_state="$(volume_record_for_state "${volume_id}" mounted)"
    if [[ -z "${mounted_state}" ]]; then
      "${ADB}" -s "${DEVICE}" shell sm mount "${volume_id}" \
        >/dev/null 2>&1 || true
    fi
  fi

  "${ADB}" -s "${DEVICE}" shell rm -rf "${EVIDENCE_ROOT}" \
    >/dev/null 2>&1 || true

  if [[ "${provisioned_virtual_disk}" == true ]]; then
    mounted_state="$(volume_record_for_state "${volume_id}" mounted)"
    if [[ -n "${mounted_state}" ]]; then
      sm_output unmount "${volume_id}" >/dev/null 2>&1 || true
    fi
    if [[ -n "${provider_id}" ]]; then
      sm_output forget "${provider_id}" >/dev/null 2>&1 || true
    fi
  fi

  if [[ "${virtual_disk_enable_attempted}" == true &&
    "${virtual_disk_cleanup_allowed}" == true ]]; then
    sm_output set-virtual-disk false >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

selected_existing_record=""
while IFS= read -r record; do
  [[ -z "${record}" ]] && continue
  candidate_id="$(argus_android_parse_public_volume_record "${record}" |
    awk '{ print $1 }')"
  candidate_metadata="$(argus_android_parse_public_volume_mount_info \
    "${candidate_id}" "${BASELINE_MOUNT_DUMP}")"
  if [[ -n "${candidate_metadata}" ]]; then
    selected_existing_record="${record}"
    break
  fi
done <<<"${BASELINE_MOUNTED_PUBLIC_RECORDS}"

if [[ -n "${selected_existing_record}" ]]; then
  # Prefer an already-mounted public volume whose backing DiskInfo advertises
  # SD/USB removability. No device storage is mutated in this branch.
  read -r volume_id volume_state provider_id < <(
    argus_android_parse_public_volume_record "${selected_existing_record}"
  )
  provider_id="$(normalize_provider_id "${provider_id}")"
  read -r disk_id mount_path < <(
    argus_android_parse_public_volume_mount_info \
      "${volume_id}" "${BASELINE_MOUNT_DUMP}"
  )
else
  if [[ -n "${BASELINE_MOUNTED_PUBLIC_RECORDS}" ]]; then
    unverified \
      'a mounted public volume exists but its removable DiskInfo could not be established'
  fi

  # `sm help` prints its capability list with a non-zero usage status on this
  # Android build; the output, not that status, is the support contract.
  sm_help="$(sm_output help 2>&1 || true)"
  if ! argus_android_sm_help_supports_commands "${sm_help}" \
    set-virtual-disk list-disks partition mount unmount; then
    unverified 'sm does not expose the required virtual-disk and mount commands'
  fi

  virtual_disk_enable_attempted=true
  if ! sm_output set-virtual-disk true >/dev/null; then
    unverified 'sm set-virtual-disk true was rejected by the connected device'
  fi

  if ! disk_id="$(wait_for_new_adoptable_disk)"; then
    unverified \
      'sm set-virtual-disk true did not expose one unique newly available adoptable disk'
  fi
  if [[ "$(record_count "${disk_id}")" -ne 1 ]]; then
    unverified 'virtual-disk provisioning exposed an ambiguous adoptable-disk delta'
  fi
  provisioned_virtual_disk=true

  if ! sm_output partition "${disk_id}" public >/dev/null; then
    unverified "sm partition ${disk_id} public was rejected"
  fi
  if ! new_volume_record="$(wait_for_new_public_volume_record)"; then
    unverified \
      'partition did not expose one unique newly created public volume before timeout'
  fi
  read -r volume_id volume_state provider_id < <(
    argus_android_parse_public_volume_record "${new_volume_record}"
  )
  provider_id="$(normalize_provider_id "${provider_id}")"
  if [[ "${volume_state}" != mounted ]]; then
    if ! sm_output mount "${volume_id}" >/dev/null; then
      unverified "sm mount ${volume_id} was rejected"
    fi
  fi
  if ! mounted_record="$(wait_for_volume_state "${volume_id}" mounted)"; then
    unverified "new public volume ${volume_id} did not become mounted before timeout"
  fi
  read -r volume_id volume_state provider_id < <(
    argus_android_parse_public_volume_record "${mounted_record}"
  )
  provider_id="$(normalize_provider_id "${provider_id}")"
fi

if [[ -z "${volume_id}" || -z "${provider_id}" || "${provider_id}" == NULL ]]; then
  unverified 'the selected public volume has no trustworthy provider identity'
fi

if ! mount_metadata="$(wait_for_removable_mount_info "${volume_id}")"; then
  unverified "StorageManager mount path for ${volume_id} was not observable before timeout"
fi
read -r observed_disk_id observed_mount_path <<<"${mount_metadata}"
if [[ "${observed_disk_id}" != "${disk_id}" ]]; then
  unverified \
    "public volume ${volume_id} is not backed by the selected disk ${disk_id}"
fi
mount_path="${observed_mount_path}"
if [[ "${mount_path}" != /storage/* || "${mount_path}" == /storage/emulated* ]]; then
  unverified "selected public volume has an unsafe transient mount path: ${mount_path}"
fi
if ! "${ADB}" -s "${DEVICE}" shell test -d "${mount_path}"; then
  unverified "selected removable mount path is not a directory: ${mount_path}"
fi

printf 'Selected removable public volume=%s provider=%s disk=%s mount=%s\n' \
  "${volume_id}" "${provider_id}" "${disk_id}" "${mount_path}"

argus_android_build_and_install "${ROOT_DIR}"
"${ADB}" -s "${DEVICE}" shell mkdir -p "${EVIDENCE_ROOT}"

printf 'Recording provider identity and LibraryRootId before unmount\n'
argus_android_run_integration "${ROOT_DIR}" \
  phase_002_android_removable_volume_test.dart \
  --dart-define=ARGUS_PHASE_002_REMOVABLE_MODE=before \
  --dart-define="ARGUS_ANDROID_REMOVABLE_EXPECTED_PROVIDER_ID=${provider_id}" \
  --dart-define="ARGUS_PHASE_002_REMOVABLE_EVIDENCE_PATH=${EVIDENCE_PATH}"
"${ADB}" -s "${DEVICE}" shell am force-stop "${PACKAGE_ID}"

printf 'Making the same physical volume unavailable with sm unmount: %s\n' \
  "${volume_id}"
if ! sm_output unmount "${volume_id}" >/dev/null; then
  unverified "sm unmount ${volume_id} was rejected; no remount claim is made"
fi
if ! wait_for_volume_state "${volume_id}" unmounted >/dev/null; then
  unverified "volume ${volume_id} did not become unmounted before timeout"
fi

printf 'Restoring the same volume identity with sm mount: %s\n' "${volume_id}"
if ! sm_output mount "${volume_id}" >/dev/null; then
  unverified "sm mount ${volume_id} was rejected; no remount claim is made"
fi
if ! remounted_record="$(wait_for_volume_state "${volume_id}" mounted)"; then
  unverified "volume ${volume_id} did not return mounted before timeout"
fi
read -r remounted_id _ remounted_provider < <(
  argus_android_parse_public_volume_record "${remounted_record}"
)
remounted_provider="$(normalize_provider_id "${remounted_provider}")"
if [[ "${remounted_id}" != "${volume_id}" ||
  "${remounted_provider}" != "${provider_id}" ]]; then
  unverified \
    'remount did not preserve the same vold/public and provider identity'
fi
if ! remounted_metadata="$(wait_for_removable_mount_info "${volume_id}")"; then
  unverified 'remounted StorageManager mount path was not observable before timeout'
fi
read -r remounted_disk _ <<<"${remounted_metadata}"
if [[ "${remounted_disk}" != "${disk_id}" ]]; then
  unverified 'remount was not backed by the same adoptable disk identity'
fi

printf 'Verifying the same provider identity and LibraryRootId after remount\n'
argus_android_run_integration "${ROOT_DIR}" \
  phase_002_android_removable_volume_test.dart \
  --dart-define=ARGUS_PHASE_002_REMOVABLE_MODE=after \
  --dart-define="ARGUS_ANDROID_REMOVABLE_EXPECTED_PROVIDER_ID=${provider_id}" \
  --dart-define="ARGUS_PHASE_002_REMOVABLE_EVIDENCE_PATH=${EVIDENCE_PATH}"

printf 'P02-005 removable-volume scenario passed with trustworthy provider remount on %s\n' \
  "${DEVICE}"

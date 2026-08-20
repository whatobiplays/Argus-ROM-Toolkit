#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/run_phase_002_android_scenario_common.sh"

baseline=$'disk:7,424\ndisk:7,500'
current=$'disk:7,424\ndisk:7,500\ndisk:7,600'
added="$(argus_android_records_added "${baseline}" "${current}")"
[[ "${added}" == 'disk:7,600' ]]

read -r volume_id state provider_id < <(
  argus_android_parse_public_volume_record 'public:7,425 mounted 0793-1B0D'
)
[[ "${volume_id}" == 'public:7,425' ]]
[[ "${state}" == 'mounted' ]]
[[ "${provider_id}" == '0793-1B0D' ]]

mount_dump=$'  DiskInfo{disk:7,424}:\n    flags=ADOPTABLE|SD size=536870912 label=Virtual\n  VolumeInfo{public:7,425}:\n    type=PUBLIC diskId=disk:7,424 state=MOUNTED\n    path=/storage/0793-1B0D internalPath=/mnt/media_rw/0793-1B0D'
read -r disk_id mount_path < <(
  argus_android_parse_public_volume_mount_info 'public:7,425' "${mount_dump}"
)
[[ "${disk_id}" == 'disk:7,424' ]]
[[ "${mount_path}" == '/storage/0793-1B0D' ]]

sm_help=$'usage: sm set-virtual-disk [true|false]\n       sm list-disks [adoptable]\n       sm partition DISK public\n       sm mount VOLUME\n       sm unmount VOLUME'
argus_android_sm_help_supports_commands "${sm_help}" \
  set-virtual-disk list-disks partition mount unmount

printf 'removable-volume helper tests passed\n'

#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "${test_root}"' EXIT

mkdir -p "${test_root}/sys/devices/virtual/powercap/psys" "${test_root}/sys/devices/virtual/powercap/core"
printf '%s\n' psys > "${test_root}/sys/devices/virtual/powercap/psys/name"
printf '%s\n' 1 > "${test_root}/sys/devices/virtual/powercap/psys/energy_uj"
printf '%s\n' core > "${test_root}/sys/devices/virtual/powercap/core/name"
printf '%s\n' 1 > "${test_root}/sys/devices/virtual/powercap/core/energy_uj"
printf '%s\n' '#!/bin/sh' 'printf '\''%s\n'\'' "$*" >> "${POWER_CAP_TEST_LOG}"' > "${test_root}/setfacl"
chmod 0755 "${test_root}/setfacl"

export POWER_CAP_SYSFS_ROOT="${test_root}/sys"
export POWER_CAP_SETFACL="${test_root}/setfacl"
export POWER_CAP_TEST_LOG="${test_root}/calls"

"${repo_root}/scripts/big-red-powercap-access" /devices/virtual/powercap/psys leo
"${repo_root}/scripts/big-red-powercap-access" /devices/virtual/powercap/core leo
"${repo_root}/scripts/big-red-powercap-access" /devices/platform/unrelated leo

[ "$(wc -l < "${test_root}/calls")" -eq 1 ]
grep -F -- '-m u:leo:r--' "${test_root}/calls" >/dev/null
grep -F -- '/devices/virtual/powercap/psys/energy_uj' "${test_root}/calls" >/dev/null

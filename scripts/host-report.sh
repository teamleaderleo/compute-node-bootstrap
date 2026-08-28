#!/usr/bin/env bash
set -euo pipefail

section() { printf '\n=== %s ===\n' "$1"; }

section DATE
date --iso-8601=seconds 2>/dev/null || date

section OS
cat /etc/os-release || true

section KERNEL
uname -a

section CPU
lscpu

section MEMORY
free -h

section BLOCK_DEVICES
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL

section DISPLAY_NETWORK_AUDIO
lspci -nnk | grep -A3 -Ei 'VGA|3D|Display|Network|Audio' || true

section NETWORK_INTERFACES
ip -brief link || true

section IP_ADDRESSES
ip -brief addr || true

section SSH
systemctl is-enabled ssh 2>/dev/null || true
systemctl is-active ssh 2>/dev/null || true

section END
printf 'Review this output before posting it publicly.\n'

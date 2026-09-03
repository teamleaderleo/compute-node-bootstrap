#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="$ROOT/scripts/install-big-red-windows-moonlight-forward"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
fakebin="$temporary/fakebin"
nft_state="$temporary/nft.rules"
reservation_state="$temporary/reservation"
service_state="$temporary/service"
runtime_target="$temporary/usr/local/sbin/big-red-windows-moonlight-forward"
unit_target="$temporary/etc/systemd/system/big-red-windows-moonlight-forward.service"
mkdir -p "$fakebin"

cat > "$fakebin/sudo" <<'SH'
#!/usr/bin/env bash
exec "$@"
SH

cat > "$fakebin/tailscale" <<'SH'
#!/usr/bin/env bash
[[ $* == 'ip -4' ]] || exit 2
printf '%s\n' 100.105.182.87
SH

cat > "$fakebin/ip" <<'SH'
#!/usr/bin/env bash
[[ ${1:-} == link && ${2:-} == show && ${3:-} == dev ]]
SH

cat > "$fakebin/nft" <<SH
#!/usr/bin/env bash
set -euo pipefail
case "\$*" in
  '-f -') /bin/cat > '$nft_state' ;;
  'list table ip big_red_windows_moonlight') [[ -f '$nft_state' ]] && /bin/cat '$nft_state' ;;
  'delete table ip big_red_windows_moonlight') /bin/rm '$nft_state' ;;
  *) exit 2 ;;
esac
SH

cat > "$fakebin/install" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == -D && ${2:-} == -m ]]
mode=$3
source=$4
target=$5
mkdir -p "$(dirname "$target")"
cp "$source" "$target"
chmod "$mode" "$target"
SH

cat > "$fakebin/sha256sum" <<'SH'
#!/usr/bin/env bash
shasum -a 256 "$@"
SH

cat > "$fakebin/virsh" <<SH
#!/usr/bin/env bash
set -euo pipefail
case "\${1:-}" in
  domiflist)
    printf '%s\n' \
      ' Interface   Type      Source    Model    MAC' \
      '-------------------------------------------------------------' \
      ' vnet1       network   default   e1000e   52:54:00:ff:0f:48'
    ;;
  net-dumpxml)
    if [[ \${BIG_RED_WINDOWS_FORWARD_TEST_CONFLICT:-0} == 1 ]]; then
      printf '%s\n' '<network><ip><dhcp><host mac="52:54:00:00:00:01" ip="192.168.122.252"/></dhcp></ip></network>'
    elif [[ -f '$reservation_state' ]]; then
      printf '%s\n' '<network><ip><dhcp><host mac="52:54:00:ff:0f:48" name="win11-starsector" ip="192.168.122.252"/></dhcp></ip></network>'
    else
      printf '%s\n' '<network><ip><dhcp/></ip></network>'
    fi
    ;;
  net-update)
    : > '$reservation_state'
    ;;
  *) exit 2 ;;
esac
SH

cat > "$fakebin/systemctl" <<SH
#!/usr/bin/env bash
set -euo pipefail
case "\$*" in
  daemon-reload) ;;
  'enable --now big-red-windows-moonlight-forward.service')
    : > '$service_state'
    '$runtime_target' apply >/dev/null
    ;;
  'is-enabled big-red-windows-moonlight-forward.service')
    [[ -f '$service_state' ]] && printf 'enabled\n'
    ;;
  'is-active big-red-windows-moonlight-forward.service')
    [[ -f '$service_state' ]] && printf 'active\n'
    ;;
  *) exit 2 ;;
esac
SH

chmod +x "$fakebin"/*
export PATH="$fakebin:/usr/bin:/bin"
export BIG_RED_WINDOWS_FORWARD_RUNTIME_TARGET="$runtime_target"
export BIG_RED_WINDOWS_FORWARD_UNIT_TARGET="$unit_target"

plan=$($INSTALLER --plan)
grep -q '^dhcp_reservation=missing$' <<<"$plan"
grep -q '^sunshine_web_ui_47990=not_forwarded$' <<<"$plan"

$INSTALLER > "$temporary/apply.out"
grep -q '^dhcp_reservation=exact$' "$temporary/apply.out"
grep -q '^system_service=enabled,active$' "$temporary/apply.out"
[[ -x "$runtime_target" && -f "$unit_target" && -f "$nft_state" ]]

$INSTALLER --verify-only > "$temporary/verify.out"
grep -q '^moonlight_forwarding=active$' "$temporary/verify.out"

if BIG_RED_WINDOWS_FORWARD_TEST_CONFLICT=1 $INSTALLER > "$temporary/conflict.out" 2>&1; then
  printf 'error: installer accepted a conflicting libvirt DHCP reservation\n' >&2
  exit 1
fi
grep -q 'libvirt DHCP reservation conflicts' "$temporary/conflict.out"

printf 'install_big_red_windows_moonlight_forward_tests=passed\n'

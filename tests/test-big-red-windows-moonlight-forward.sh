#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUNTIME="$ROOT/scripts/big-red-windows-moonlight-forward"
UNIT="$ROOT/systemd/big-red-windows-moonlight-forward.service"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
fakebin="$temporary/fakebin"
state="$temporary/nft.rules"
mkdir -p "$fakebin"

cat > "$fakebin/sudo" <<'SH'
#!/usr/bin/env bash
exec "$@"
SH

cat > "$fakebin/tailscale" <<'SH'
#!/usr/bin/env bash
if [[ $* == 'ip -4' ]]; then
  printf '%s\n' 100.105.182.87
else
  exit 2
fi
SH

cat > "$fakebin/ip" <<'SH'
#!/usr/bin/env bash
[[ ${1:-} == link && ${2:-} == show && ${3:-} == dev ]]
SH

cat > "$fakebin/nft" <<SH
#!/usr/bin/env bash
set -euo pipefail
case "\$*" in
  '-f -') /bin/cat > '$state' ;;
  'list table ip big_red_windows_moonlight') [[ -f '$state' ]] && /bin/cat '$state' ;;
  'delete table ip big_red_windows_moonlight') : > '$state.deleted'; /bin/rm '$state' ;;
  *) exit 2 ;;
esac
SH

chmod +x "$fakebin"/*
export PATH="$fakebin:/usr/bin:/bin"

plan=$($RUNTIME plan)
grep -q '^tailnet_interface=tailscale0$' <<<"$plan"
grep -q '^forward_tcp=47984,47989,48010$' <<<"$plan"
grep -q '^forward_udp=47998-48000$' <<<"$plan"
grep -q '^sunshine_web_ui_47990=not_forwarded$' <<<"$plan"

$RUNTIME apply > "$temporary/apply.out"
grep -q '^moonlight_forwarding=active$' "$temporary/apply.out"
grep -q 'iifname "tailscale0" ip daddr 100.105.182.87' "$state"
grep -q 'dnat to 192.168.122.252' "$state"
grep -q 'snat to 192.168.122.1' "$state"
if grep -Eq 'dport .*47990' "$state"; then
  printf 'error: test rules expose Sunshine Web UI port 47990\n' >&2
  exit 1
fi

$RUNTIME verify > "$temporary/verify.out"
grep -q '^tailnet_front_door=100.105.182.87$' "$temporary/verify.out"
$RUNTIME remove > "$temporary/remove.out"
grep -q '^moonlight_forwarding=removed$' "$temporary/remove.out"
[[ ! -f "$state" ]]

grep -q '^Requires=tailscaled.service libvirtd.service$' "$UNIT"
grep -q '^ExecStart=/usr/local/sbin/big-red-windows-moonlight-forward apply$' "$UNIT"
grep -q '^ExecStop=/usr/local/sbin/big-red-windows-moonlight-forward remove$' "$UNIT"
grep -q '^RemainAfterExit=yes$' "$UNIT"

printf 'big_red_windows_moonlight_forward_tests=passed\n'

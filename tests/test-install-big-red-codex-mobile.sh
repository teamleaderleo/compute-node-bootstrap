#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="$ROOT/scripts/install-big-red-codex-mobile"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
home="$temporary/home"
fakebin="$temporary/fakebin"
log="$temporary/commands.log"
user=$(id -un)
uid=$(id -u)
mkdir -p "$home/Projects/compute-node-bootstrap/scripts" "$fakebin"

cat > "$home/Projects/compute-node-bootstrap/scripts/install-big-red-codex-muse" <<'SH'
#!/usr/bin/env bash
[[ ${1:-} == --verify-only ]]
SH

cat > "$fakebin/getent" <<SH
#!/usr/bin/env bash
if [[ \${1:-} == passwd && \${2:-} == $user ]]; then
  printf '%s\n' '$user:x:$uid:$uid:Test User:$home:/bin/bash'
  exit 0
fi
exit 2
SH
cat > "$fakebin/sudo" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == -u ]]; then shift 2; fi
exec "$@"
SH
cat > "$fakebin/loginctl" <<SH
#!/usr/bin/env bash
if [[ \${1:-} == show-user ]]; then printf 'yes\n'; exit 0; fi
printf 'loginctl=<%s>\n' "\$*" >> '$log'
SH
cat > "$fakebin/systemctl" <<SH
#!/usr/bin/env bash
case "\$*" in
  '--user is-enabled big-red-codex-mobile.service') printf 'enabled\n' ;;
  '--user is-active big-red-codex-mobile.service') printf 'active\n' ;;
  *) printf 'systemctl=<%s>\n' "\$*" >> '$log' ;;
esac
SH
cat > "$fakebin/tailscale" <<SH
#!/usr/bin/env bash
case "\$*" in
  'status --json') printf '%s\n' '{"Self":{"DNSName":"big-red.example.ts.net."}}' ;;
  'serve status --json') printf '%s\n' '{"TCP":{"443":{"HTTPS":true},"8444":{"HTTPS":true}},"Web":{"big-red.example.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:4096"}}},"big-red.example.ts.net:8444":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:7681"}}}}}' ;;
  serve*) printf 'tailscale=<%s>\n' "\$*" >> '$log' ;;
  *) exit 2 ;;
esac
SH
cat > "$fakebin/ss" <<'SH'
#!/usr/bin/env bash
if [[ ${BIG_RED_CODEX_MOBILE_TEST_PUBLIC_LISTENER:-0} == 1 ]]; then
  printf '%s\n' 'LISTEN 0 4096 0.0.0.0:7681 0.0.0.0:*'
else
  printf '%s\n' 'LISTEN 0 4096 127.0.0.1:7681 0.0.0.0:*'
fi
SH
cat > "$fakebin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '<!doctype html><title>ttyd</title>'
SH
cat > "$fakebin/ttyd" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat > "$fakebin/tmux" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$home/Projects/compute-node-bootstrap/scripts/install-big-red-codex-muse" "$fakebin"/*
export PATH="$fakebin:$PATH"

plan=$($INSTALLER --plan)
grep -q '^local_bind=127.0.0.1:7681$' <<<"$plan"
grep -q '^tailscale_https_url=https://big-red.example.ts.net:8444/$' <<<"$plan"
grep -q '^profiles=muse-xhigh,muse-high,sol-default$' <<<"$plan"

$INSTALLER >/dev/null
cmp -s "$ROOT/scripts/big-red-codex-mobile" "$home/.local/bin/big-red-codex-mobile"
cmp -s "$ROOT/systemd/big-red-codex-mobile.service" "$home/.config/systemd/user/big-red-codex-mobile.service"
grep -q 'tailscale=<serve --bg --yes --https=8444 http://127.0.0.1:7681>' "$log"

$INSTALLER --verify-only >/dev/null
if BIG_RED_CODEX_MOBILE_TEST_PUBLIC_LISTENER=1 $INSTALLER --verify-only >/dev/null 2>&1; then
  printf 'verify accepted a public listener\n' >&2
  exit 1
fi

grep -q -- '--interface 127.0.0.1 --port 7681' "$ROOT/systemd/big-red-codex-mobile.service"
grep -q -- "codex -p \"\$profile\"" "$ROOT/scripts/big-red-codex-mobile"
if grep -Rqs 'muse-max' "$ROOT/scripts/big-red-codex-mobile" "$ROOT/systemd/big-red-codex-mobile.service" "$ROOT/docs/BIG_RED_CODEX_MOBILE.md"; then
  printf 'obsolete muse-max profile found\n' >&2
  exit 1
fi

printf 'ok: Codex mobile installer preserves loopback, Tailscale, and profile boundaries\n'

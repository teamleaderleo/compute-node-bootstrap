#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="$ROOT/scripts/install-big-red-opencode-web"
UNIT="$ROOT/systemd/big-red-opencode-web.service"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
home="$temporary/home"
fakebin="$temporary/fakebin"
log="$temporary/commands.log"
user=$(id -un)
uid=$(id -u)
mkdir -p "$home/.local/bin" "$home/Projects/compute-node-bootstrap" "$home/Projects/leo-workspace" "$fakebin"

cat > "$home/.local/bin/opencode" <<'SH'
#!/usr/bin/env bash
if [[ ${1:-} == models && ${2:-} == opencode ]]; then
  printf '%s\n' opencode/muse-spark-1.3-contributor-free
  exit 0
fi
exit 2
SH
chmod +x "$home/.local/bin/opencode"

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
  '--user is-enabled big-red-opencode-web.service') printf 'enabled\n' ;;
  '--user is-active big-red-opencode-web.service') printf 'active\n' ;;
  *) printf 'systemctl=<%s>\n' "\$*" >> '$log' ;;
esac
SH

cat > "$fakebin/tailscale" <<SH
#!/usr/bin/env bash
case "\$*" in
  'status --json') printf '%s\n' '{"Self":{"DNSName":"big-red.example.ts.net."}}' ;;
  'serve status --json') printf '%s\n' '{"Web":{"big-red.example.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:4096"}}}}}' ;;
  'funnel status --json') printf '%s\n' '{}' ;;
  serve*) printf 'tailscale=<%s>\n' "\$*" >> '$log' ;;
  *) exit 2 ;;
esac
SH

cat > "$fakebin/ss" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'LISTEN 0 4096 127.0.0.1:4096 0.0.0.0:*'
SH

cat > "$fakebin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
configured=false
url=
while (($#)); do
  case "$1" in
    --config) configured=true; read -r _; shift 2 ;;
    http://*) url=$1; shift ;;
    *) shift ;;
  esac
done
if [[ "$configured" == false ]]; then
  printf '401'
elif [[ "$url" == */global/health ]]; then
  printf '%s\n' '{"healthy":true,"version":"test"}'
elif [[ "$url" == */path ]]; then
  printf '%s\n' "{\"worktree\":\"/\",\"directory\":\"$HOME/Projects\"}"
elif [[ "$url" == *'/file?path=.' ]]; then
  printf '%s\n' '[{"name":"compute-node-bootstrap"},{"name":"leo-workspace"}]'
else
  exit 2
fi
SH

chmod +x "$fakebin"/*
export PATH="$fakebin:$PATH"

grep -q 'OPENCODE_SERVER_PASSWORD' "$UNIT"
grep -q -- '--hostname 127.0.0.1 --port 4096' "$UNIT"
if grep -q -- '--hostname 0.0.0.0' "$UNIT"; then
  printf 'error: unit exposes OpenCode Web beyond loopback\n' >&2
  exit 1
fi

plan=$($INSTALLER --plan --operator-user "$user")
grep -q '^local_bind=127.0.0.1:4096$' <<<"$plan"
grep -q '^tailscale_https_url=https://big-red.example.ts.net/$' <<<"$plan"
grep -q '^credential_mode=0600$' <<<"$plan"
grep -q '^public_funnel=disabled$' <<<"$plan"

$INSTALLER --operator-user "$user" > "$temporary/apply.out"
grep -q '^server_password_status=created$' "$temporary/apply.out"
grep -q '^user_service=enabled,active$' "$temporary/apply.out"
grep -q '^tailscale_funnel=disabled$' "$temporary/apply.out"
grep -q '^muse_model=opencode/muse-spark-1.3-contributor-free$' "$temporary/apply.out"
[[ -s "$home/.config/big-red-opencode-web/server-password" ]]
[[ $(stat -c '%a' "$home/.config/big-red-opencode-web/server-password") == 600 ]]
[[ -f "$home/.config/systemd/user/big-red-opencode-web.service" ]]
grep -q 'tailscale=<serve --bg --yes --https=443 http://127.0.0.1:4096>' "$log"

$INSTALLER --verify-only --operator-user "$user" > "$temporary/verify.out"
grep -q '^server_password=configured$' "$temporary/verify.out"
if grep -Fq "$(tr -d '\n' < "$home/.config/big-red-opencode-web/server-password")" \
  "$temporary/apply.out" "$temporary/verify.out" "$log"; then
  printf 'error: OpenCode Web password leaked into test output\n' >&2
  exit 1
fi

printf 'install_big_red_opencode_web_tests=passed\n'

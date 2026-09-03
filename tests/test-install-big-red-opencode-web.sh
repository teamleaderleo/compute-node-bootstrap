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
  if [[ ${BIG_RED_OPENCODE_WEB_TEST_MODEL_LOOKALIKE:-0} == 1 ]]; then
    printf '%s\n' opencode/muse-spark-1x3-contributor-free
  else
    printf '%s\n' opencode/muse-spark-1.3-contributor-free
  fi
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
  'serve status --json')
    if [[ \${BIG_RED_OPENCODE_WEB_TEST_FUNNEL:-0} == 1 ]]; then
      printf '%s\n' '{"TCP":{"443":{"HTTPS":true}},"Web":{"big-red.example.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:4096"}}}},"AllowFunnel":{"big-red.example.ts.net:443":true}}'
    elif [[ \${BIG_RED_OPENCODE_WEB_TEST_WRONG_SERVE:-0} == 1 ]]; then
      printf '%s\n' '{"TCP":{"443":{"HTTPS":true}},"Web":{"big-red.example.ts.net:443":{"Handlers":{"/other":{"Proxy":"http://127.0.0.1:4096"}}}}}'
    else
      printf '%s\n' '{"TCP":{"443":{"HTTPS":true}},"Web":{"big-red.example.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:4096"}}}}}'
    fi
    ;;
  serve*) printf 'tailscale=<%s>\n' "\$*" >> '$log' ;;
  *) exit 2 ;;
esac
SH

cat > "$fakebin/ss" <<'SH'
#!/usr/bin/env bash
if [[ ${BIG_RED_OPENCODE_WEB_TEST_PUBLIC_LISTENER:-0} == 1 ]]; then
  printf '%s\n' 'LISTEN 0 4096 0.0.0.0:4096 0.0.0.0:*'
else
  printf '%s\n' 'LISTEN 0 4096 127.0.0.1:4096 0.0.0.0:*'
fi
SH

cat > "$fakebin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
configured=false
url=
write_code=false
while (($#)); do
  case "$1" in
    --write-out) write_code=true; shift 2 ;;
    http://*) url=$1; shift ;;
    *) shift ;;
  esac
done
if [[ ${BIG_RED_OPENCODE_WEB_TEST_AUTH_REQUIRED:-0} == 1 ]]; then
  printf '401'
elif [[ "$write_code" == true ]]; then
  printf '200'
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

if grep -q 'OPENCODE_SERVER_PASSWORD\|LoadCredential' "$UNIT"; then
  printf 'error: unit still enables browser Basic Auth\n' >&2
  exit 1
fi
grep -q -- '--hostname 127.0.0.1 --port 4096' "$UNIT"
if grep -q -- '--hostname 0.0.0.0' "$UNIT"; then
  printf 'error: unit exposes OpenCode Web beyond loopback\n' >&2
  exit 1
fi

plan=$($INSTALLER --plan --operator-user "$user")
grep -q '^local_bind=127.0.0.1:4096$' <<<"$plan"
grep -q '^tailscale_https_url=https://big-red.example.ts.net/$' <<<"$plan"
grep -q '^browser_auth=tailnet_only$' <<<"$plan"
grep -q '^public_funnel=disabled$' <<<"$plan"

$INSTALLER --operator-user "$user" > "$temporary/apply.out"
grep -q '^user_service=enabled,active$' "$temporary/apply.out"
grep -q '^tailscale_funnel=disabled$' "$temporary/apply.out"
grep -q '^muse_model=opencode/muse-spark-1.3-contributor-free$' "$temporary/apply.out"
[[ -f "$home/.config/systemd/user/big-red-opencode-web.service" ]]
grep -q 'tailscale=<serve --bg --yes --https=443 http://127.0.0.1:4096>' "$log"

$INSTALLER --verify-only --operator-user "$user" > "$temporary/verify.out"
grep -q '^opencode_web_browser_auth=tailnet_only$' "$temporary/verify.out"
if BIG_RED_OPENCODE_WEB_TEST_AUTH_REQUIRED=1 $INSTALLER --verify-only --operator-user "$user" \
  > "$temporary/auth.out" 2>&1; then
  printf 'error: verifier accepted an auth-challenged browser route\n' >&2
  exit 1
fi
grep -q 'did not become login-free and ready' "$temporary/auth.out"
if BIG_RED_OPENCODE_WEB_TEST_FUNNEL=1 $INSTALLER --verify-only --operator-user "$user" \
  > "$temporary/funnel.out" 2>&1; then
  printf 'error: verifier accepted a public Funnel configuration\n' >&2
  exit 1
fi
grep -q 'Tailscale Funnel must remain disabled' "$temporary/funnel.out"
if BIG_RED_OPENCODE_WEB_TEST_WRONG_SERVE=1 $INSTALLER --verify-only --operator-user "$user" \
  > "$temporary/serve.out" 2>&1; then
  printf 'error: verifier accepted a stale Serve handler\n' >&2
  exit 1
fi
grep -q 'root handler is not the exact OpenCode loopback proxy' "$temporary/serve.out"
if BIG_RED_OPENCODE_WEB_TEST_PUBLIC_LISTENER=1 $INSTALLER --verify-only --operator-user "$user" \
  > "$temporary/listener.out" 2>&1; then
  printf 'error: verifier accepted a public OpenCode listener\n' >&2
  exit 1
fi
grep -q 'listener is not exactly loopback' "$temporary/listener.out"
if BIG_RED_OPENCODE_WEB_TEST_MODEL_LOOKALIKE=1 $INSTALLER --verify-only --operator-user "$user" \
  > "$temporary/model.out" 2>&1; then
  printf 'error: verifier accepted a regex-only model match\n' >&2
  exit 1
fi

cp "$home/.config/systemd/user/big-red-opencode-web.service" "$temporary/unit.backup"
printf '\n# mismatch\n' >> "$home/.config/systemd/user/big-red-opencode-web.service"
if $INSTALLER --verify-only --operator-user "$user" > "$temporary/unit.out" 2>&1; then
  printf 'error: verifier accepted a mismatched unit\n' >&2
  exit 1
fi
mv "$temporary/unit.backup" "$home/.config/systemd/user/big-red-opencode-web.service"

printf 'install_big_red_opencode_web_tests=passed\n'

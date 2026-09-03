#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="$ROOT/scripts/install-big-red-codex-muse"
TOKEN_HELPER="$ROOT/scripts/opencode-zen-codex-token"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
home="$temporary/home"
fakebin="$temporary/fakebin"
mkdir -p "$home/.local/bin" "$home/.local/share/opencode" "$home/.codex" "$fakebin"

bash -n "$INSTALLER"
bash -n "$TOKEN_HELPER"

cat > "$fakebin/getent" <<SH
#!/usr/bin/env bash
if [[ \${1:-} == passwd && \${2:-} == muse-test ]]; then
  printf '%s\n' 'muse-test:x:12345:12345:Muse Test:$home:/bin/bash'
  exit 0
fi
exit 2
SH
chmod +x "$fakebin/getent"

cat > "$fakebin/sudo" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == -u ]] || exit 2
shift 2
exec "$@"
SH
chmod +x "$fakebin/sudo"

cat > "$home/.local/bin/codex" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ " $* " == *' --version '* || ${1:-} == --version ]]; then
  printf 'codex-cli fake-1.0\n'
  exit 0
fi
exit 2
SH
chmod +x "$home/.local/bin/codex"

cat > "$home/.local/share/opencode/auth.json" <<'JSON'
{"opencode":{"type":"api","key":"test-only-zen-key"}}
JSON
chmod 600 "$home/.local/share/opencode/auth.json"
cat > "$home/.codex/config.toml" <<'TOML'
model = "gpt-5.6-sol"
model_reasoning_effort = "high"
TOML
cat > "$home/.codex/muse-max.config.toml" <<'TOML'
# Managed by install-big-red-codex-muse.
model = "obsolete"
TOML
base_before=$(sha256sum "$home/.codex/config.toml" | awk '{print $1}')

export PATH="$fakebin:$PATH"
plan=$($INSTALLER --plan --operator-user muse-test)
grep -q '^base_config_modified=no$' <<<"$plan"
grep -q '^provider=opencode_zen$' <<<"$plan"
grep -q '^provider_base_url=https://opencode.ai/zen/v1$' <<<"$plan"
grep -q '^wire_api=responses$' <<<"$plan"
grep -q '^model=muse-spark-1.3-contributor-free$' <<<"$plan"
grep -q '^profiles=muse-high,muse-xhigh$' <<<"$plan"
grep -q '^profile_efforts=high,xhigh$' <<<"$plan"
grep -q '^obsolete_profile_removed=muse-max$' <<<"$plan"
grep -q '^authentication=command_backed_existing_opencode_credential$' <<<"$plan"
grep -q '^credential_value_copied=no$' <<<"$plan"

$INSTALLER --operator-user muse-test > "$temporary/apply.out"
grep -q '^codex_install=verified$' "$temporary/apply.out"
grep -q '^zen_auth=verified$' "$temporary/apply.out"
[[ -x "$home/.local/libexec/opencode-zen-codex-token" ]]
token=$(
  HOME="$home" XDG_DATA_HOME= OPENCODE_AUTH_FILE= \
    "$home/.local/libexec/opencode-zen-codex-token"
)
[[ "$token" == test-only-zen-key ]]
[[ ! -e "$home/.codex/muse-max.config.toml" ]]

for pair in muse-high:high muse-xhigh:xhigh; do
  profile=${pair%%:*}
  effort=${pair##*:}
  path="$home/.codex/$profile.config.toml"
  [[ -f "$path" && $(stat -c %a "$path" 2>/dev/null || stat -f %Lp "$path") == 600 ]]
  grep -q '^model_provider = "opencode_zen"$' "$path"
  grep -q '^model = "muse-spark-1.3-contributor-free"$' "$path"
  grep -q "^model_reasoning_effort = \"$effort\"$" "$path"
  grep -q '^base_url = "https://opencode.ai/zen/v1"$' "$path"
  grep -q '^wire_api = "responses"$' "$path"
  grep -q "^command = \"$home/.local/libexec/opencode-zen-codex-token\"$" "$path"
  grep -q '^apps = false$' "$path"
  grep -q '^plugins = false$' "$path"
  grep -q '^multi_agent = false$' "$path"
done

base_after=$(sha256sum "$home/.codex/config.toml" | awk '{print $1}')
[[ "$base_before" == "$base_after" ]]
$INSTALLER --verify-only --operator-user muse-test > "$temporary/verify.out"
grep -q '^codex_version=codex-cli fake-1.0$' "$temporary/verify.out"

chmod 644 "$home/.local/share/opencode/auth.json"
if "$INSTALLER" --verify-only --operator-user muse-test >/dev/null 2>&1; then
  printf 'error: verification accepted a group/world-readable credential store\n' >&2
  exit 1
fi
chmod 600 "$home/.local/share/opencode/auth.json"

rm "$home/.codex/muse-high.config.toml"
printf '%s\n' 'model = "unmanaged"' > "$home/.codex/muse-high.config.toml"
if "$INSTALLER" --operator-user muse-test >/dev/null 2>&1; then
  printf 'error: installer replaced an unmanaged profile\n' >&2
  exit 1
fi

if grep -q 'test-only-zen-key' "$INSTALLER" "$TOKEN_HELPER" "$ROOT"/codex/*.in; then
  printf 'error: implementation source contains a test credential\n' >&2
  exit 1
fi

printf 'install_big_red_codex_muse_tests=passed\n'

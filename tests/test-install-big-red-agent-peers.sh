#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="$ROOT/scripts/install-big-red-agent-peers"
PEER="$ROOT/scripts/big-red-agent-peer"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

bash -n "$INSTALLER"
bash -n "$PEER"

plan=$($INSTALLER --plan --operator-user "$(id -un)")
grep -q '^claude_channel=stable$' <<<"$plan"
grep -q '^claude_installer=https://claude.ai/install.sh$' <<<"$plan"
grep -q '^claude_launcher_relative=.local/bin/claude$' <<<"$plan"
grep -q '^claude_delegate_model=claude-opus-5$' <<<"$plan"
grep -q '^claude_delegate_effort=high$' <<<"$plan"
grep -q '^antigravity_installer=https://antigravity.google/cli/install.sh$' <<<"$plan"
grep -q '^antigravity_launcher_relative=.local/bin/agy$' <<<"$plan"
grep -q '^antigravity_installer_flags=--dir .local/bin$' <<<"$plan"
grep -q '^antigravity_installer_home=isolated_temporary_home$' <<<"$plan"
grep -q '^antigravity_delegate_model=gemini-3.7-flash-high$' <<<"$plan"
grep -q '^antigravity_delegate_effort=high$' <<<"$plan"
grep -q '^peer_launcher_relative=.local/bin/big-red-agent-peer$' <<<"$plan"
grep -q '^peer_usage_ledger_relative=.local/state/big-red-agent-peer/usage.jsonl$' <<<"$plan"
grep -q '^delegated_agent_mode=full_unattended$' <<<"$plan"
grep -q '^provider_authentication=separate_interactive_step$' <<<"$plan"
grep -q '^credential_files_read=none$' <<<"$plan"

installer_text=$(cat "$INSTALLER")
peer_text=$(cat "$PEER")
grep -q 'bash "$claude_installer" stable' <<<"$installer_text"
grep -q 'bash "$antigravity_installer" --dir "$local_bin"' <<<"$installer_text"
grep -q 'HOME="$antigravity_installer_home"' <<<"$installer_text"
grep -q 'claude_model=${BIG_RED_CLAUDE_MODEL:-claude-opus-5}' <<<"$peer_text"
grep -q 'claude_effort=${BIG_RED_CLAUDE_EFFORT:-high}' <<<"$peer_text"
grep -q 'antigravity_model=${BIG_RED_ANTIGRAVITY_MODEL:-gemini-3.7-flash-high}' <<<"$peer_text"
grep -q 'antigravity_effort=${BIG_RED_ANTIGRAVITY_EFFORT:-high}' <<<"$peer_text"
grep -q -- '--dangerously-skip-permissions' <<<"$peer_text"
grep -q 'big-red-agent-peer-usage/v1' <<<"$peer_text"
grep -q 'big-red-agent-peer-usage-summary/v1' <<<"$peer_text"
if grep -qE -- '--safe-mode|--sandbox|--tools' <<<"$peer_text"; then
  printf 'error: peer launcher contains a restricted-capability flag\n' >&2
  exit 1
fi
if grep -qE 'GEMINI_API_KEY=|ANTHROPIC_API_KEY=' <<<"$installer_text"; then
  printf 'error: installer contains a provider API credential assignment\n' >&2
  exit 1
fi

fake_home="$temporary/home"
fake_bin="$temporary/bin"
mkdir -p "$fake_home/.local/bin" "$fake_bin"
install -m 0755 "$PEER" "$fake_home/.local/bin/big-red-agent-peer"

cat > "$fake_bin/getent" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == passwd && $# -eq 2 ]]
printf '%s:x:1000:1000:Peer Test:%s:/bin/bash\n' "$2" "${FAKE_OPERATOR_HOME:?}"
SH
chmod +x "$fake_bin/getent"

cat > "$fake_home/.local/bin/claude" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --version) printf 'claude fake 1.0\n' ;;
  --help) printf '%s\n' '--dangerously-skip-permissions --model --effort --output-format' ;;
  *) exit 2 ;;
esac
SH
chmod +x "$fake_home/.local/bin/claude"

cat > "$fake_home/.local/bin/agy" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --version) printf 'agy fake 1.0\n' ;;
  --help) printf '%s\n' '--dangerously-skip-permissions --model --effort --output-format --print-timeout' >&2 ;;
  *) exit 2 ;;
esac
SH
chmod +x "$fake_home/.local/bin/agy"

verified=$(
  FAKE_OPERATOR_HOME="$fake_home" PATH="$fake_bin:$PATH" \
    "$INSTALLER" --verify-only --operator-user "$(id -un)"
)
grep -q '^claude_install=verified$' <<<"$verified"
grep -q '^antigravity_install=verified$' <<<"$verified"

fake_claude_installer="$temporary/claude-install.sh"
fake_antigravity_installer="$temporary/antigravity-install.sh"
fake_install_log="$temporary/install.log"
cat > "$fake_claude_installer" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == stable ]]
printf 'claude_home=%s\n' "$HOME" >> "${FAKE_INSTALL_LOG:?}"
SH
cat > "$fake_antigravity_installer" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == --dir && ${2:-} == "${FAKE_OPERATOR_HOME:?}/.local/bin" ]]
[[ "$HOME" != "$FAKE_OPERATOR_HOME" ]]
case "$HOME" in
  "$FAKE_OPERATOR_HOME"/.cache/big-red-agent-peers-install.*/antigravity-home) ;;
  *) printf 'error: Antigravity installer HOME was not isolated: %s\n' "$HOME" >&2; exit 1 ;;
esac
printf 'antigravity_home=%s\n' "$HOME" >> "${FAKE_INSTALL_LOG:?}"
SH

cat > "$fake_bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
destination=
url=
while (($#)); do
  case "$1" in
    --output) destination=$2; shift 2 ;;
    https://*) url=$1; shift ;;
    *) shift ;;
  esac
done
[[ -n "$destination" && -n "$url" ]]
case "$url" in
  https://claude.ai/install.sh) cp "${FAKE_CLAUDE_INSTALLER:?}" "$destination" ;;
  https://antigravity.google/cli/install.sh) cp "${FAKE_ANTIGRAVITY_INSTALLER:?}" "$destination" ;;
  *) exit 22 ;;
esac
SH
chmod +x "$fake_bin/curl" "$fake_claude_installer" "$fake_antigravity_installer"

FAKE_OPERATOR_HOME="$fake_home" \
FAKE_CLAUDE_INSTALLER="$fake_claude_installer" \
FAKE_ANTIGRAVITY_INSTALLER="$fake_antigravity_installer" \
FAKE_INSTALL_LOG="$fake_install_log" \
PATH="$fake_bin:$PATH" \
  "$INSTALLER" --operator-user "$(id -un)" >/dev/null
grep -q "^claude_home=$fake_home$" "$fake_install_log"
grep -q "^antigravity_home=$fake_home/.cache/big-red-agent-peers-install\..*/antigravity-home$" "$fake_install_log"
if find "$fake_home/.cache" -maxdepth 1 -type d -name 'big-red-agent-peers-install.*' | grep -q .; then
  printf 'error: successful installer left its temporary directory behind\n' >&2
  exit 1
fi

cat > "$fake_antigravity_installer" <<'SH'
#!/usr/bin/env bash
exit 23
SH
if FAKE_OPERATOR_HOME="$fake_home" \
   FAKE_CLAUDE_INSTALLER="$fake_claude_installer" \
   FAKE_ANTIGRAVITY_INSTALLER="$fake_antigravity_installer" \
   FAKE_INSTALL_LOG="$fake_install_log" \
   PATH="$fake_bin:$PATH" \
     "$INSTALLER" --operator-user "$(id -un)" >/dev/null 2>&1; then
  printf 'error: installer ignored an Antigravity installer failure\n' >&2
  exit 1
fi
if find "$fake_home/.cache" -maxdepth 1 -type d -name 'big-red-agent-peers-install.*' | grep -q .; then
  printf 'error: failed installer left its temporary directory behind\n' >&2
  exit 1
fi

printf 'install_big_red_agent_peers_tests=passed\n'

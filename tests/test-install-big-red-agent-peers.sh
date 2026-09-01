#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="$ROOT/scripts/install-big-red-agent-peers"
PEER="$ROOT/scripts/big-red-agent-peer"

bash -n "$INSTALLER"
bash -n "$PEER"

plan=$($INSTALLER --plan --operator-user "$(id -un)")
grep -q '^claude_channel=stable$' <<<"$plan"
grep -q '^claude_installer=https://claude.ai/install.sh$' <<<"$plan"
grep -q '^claude_launcher_relative=.local/bin/claude$' <<<"$plan"
grep -q '^antigravity_installer=https://antigravity.google/cli/install.sh$' <<<"$plan"
grep -q '^antigravity_launcher_relative=.local/bin/agy$' <<<"$plan"
grep -q '^antigravity_installer_flags=--skip-path --skip-aliases$' <<<"$plan"
grep -q '^peer_launcher_relative=.local/bin/big-red-agent-peer$' <<<"$plan"
grep -q '^peer_launcher_sha256=[0-9a-f]\{64\}$' <<<"$plan"
grep -q '^provider_authentication=separate_interactive_step$' <<<"$plan"
grep -q '^credential_files_read=none$' <<<"$plan"
! grep -qiE 'token|cookie|password|secret' <<<"$(grep -v credential_files_read <<<"$plan")"

source_text=$(cat "$INSTALLER")
grep -q 'bash "$claude_installer" stable' <<<"$source_text"
grep -q 'bash "$antigravity_installer" --skip-path --skip-aliases' <<<"$source_text"
grep -q 'install -m 0755 "$peer_source" "$peer_launcher"' <<<"$source_text"
grep -q -- '--safe-mode' <<<"$source_text"
grep -q -- '--sandbox' <<<"$source_text"
grep -q -- '--print-timeout' <<<"$source_text"
! grep -qE 'auth login|/login|GEMINI_API_KEY=|ANTHROPIC_API_KEY=' <<<"$source_text"

printf 'install_big_red_agent_peers_tests=passed\n'

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
grep -q '^claude_delegate_model=claude-opus-5$' <<<"$plan"
grep -q '^claude_delegate_effort=high$' <<<"$plan"
grep -q '^antigravity_installer=https://antigravity.google/cli/install.sh$' <<<"$plan"
grep -q '^antigravity_launcher_relative=.local/bin/agy$' <<<"$plan"
grep -q '^antigravity_installer_flags=--skip-path --skip-aliases$' <<<"$plan"
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
grep -q 'bash "$antigravity_installer" --skip-path --skip-aliases' <<<"$installer_text"
grep -q 'claude_model=${BIG_RED_CLAUDE_MODEL:-claude-opus-5}' <<<"$peer_text"
grep -q 'claude_effort=${BIG_RED_CLAUDE_EFFORT:-high}' <<<"$peer_text"
grep -q 'antigravity_model=${BIG_RED_ANTIGRAVITY_MODEL:-gemini-3.7-flash-high}' <<<"$peer_text"
grep -q 'antigravity_effort=${BIG_RED_ANTIGRAVITY_EFFORT:-high}' <<<"$peer_text"
grep -q -- '--dangerously-skip-permissions' <<<"$peer_text"
grep -q 'big-red-agent-peer-usage/v1' <<<"$peer_text"
grep -q 'big-red-agent-peer-usage-summary/v1' <<<"$peer_text"
! grep -q -- '--safe-mode' <<<"$peer_text"
! grep -q -- '--sandbox' <<<"$peer_text"
! grep -q -- '--tools' <<<"$peer_text"
! grep -qE 'GEMINI_API_KEY=|ANTHROPIC_API_KEY=' <<<"$installer_text"

printf 'install_big_red_agent_peers_tests=passed\n'

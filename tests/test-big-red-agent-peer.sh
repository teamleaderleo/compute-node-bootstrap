#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PEER="$ROOT/scripts/big-red-agent-peer"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
home="$temporary/home"
project="$temporary/project"
log_root="$temporary/provider-log"
mkdir -p "$home/.local/bin" "$project"

git -C "$project" init -q
git -C "$project" config user.name 'Peer Test'
git -C "$project" config user.email peer@example.invalid
printf 'base\n' > "$project/tracked.txt"
git -C "$project" add tracked.txt
git -C "$project" commit -qm base

cat > "$home/.local/bin/claude" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
log=${BIG_RED_AGENT_TEST_LOG:?}.claude
{
  printf 'cwd=%s\n' "$PWD"
  printf 'home=%s\n' "$HOME"
  printf 'github_token=%s\n' "${GITHUB_TOKEN:-}"
  printf 'ssh_auth_sock=%s\n' "${SSH_AUTH_SOCK:-}"
  printf 'anthropic_api=%s\n' "${ANTHROPIC_API_KEY:-}"
  printf 'anthropic_base_url=%s\n' "${ANTHROPIC_BASE_URL:-}"
  printf 'claude_bedrock=%s\n' "${CLAUDE_CODE_USE_BEDROCK:-}"
  printf 'gemini_api=%s\n' "${GEMINI_API_KEY:-}"
  printf 'openai_api=%s\n' "${OPENAI_API_KEY:-}"
  printf 'argv='; printf '<%s>' "$@"; printf '\n'
} > "$log"
printf '%s\n' '{"subtype":"success","result":"fake claude result","total_cost_usd":1.25,"usage":{"input_tokens":100,"cache_creation_input_tokens":50,"cache_read_input_tokens":850,"output_tokens":25}}'
SH
chmod +x "$home/.local/bin/claude"

cat > "$home/.local/bin/agy" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
log=${BIG_RED_AGENT_TEST_LOG:?}.antigravity
{
  printf 'cwd=%s\n' "$PWD"
  printf 'home=%s\n' "$HOME"
  printf 'github_token=%s\n' "${GITHUB_TOKEN:-}"
  printf 'ssh_auth_sock=%s\n' "${SSH_AUTH_SOCK:-}"
  printf 'anthropic_api=%s\n' "${ANTHROPIC_API_KEY:-}"
  printf 'google_api=%s\n' "${GOOGLE_API_KEY:-}"
  printf 'google_genai_vertex=%s\n' "${GOOGLE_GENAI_USE_VERTEXAI:-}"
  printf 'gemini_api=%s\n' "${GEMINI_API_KEY:-}"
  printf 'openai_api=%s\n' "${OPENAI_API_KEY:-}"
  printf 'argv='; printf '<%s>' "$@"; printf '\n'
} > "$log"
printf 'peer touched live worktree\n' > peer-write.txt
printf '%s\n' '{"conversation_id":"private-not-recorded","status":"SUCCESS","response":"fake antigravity result","duration_seconds":3.5,"num_turns":1,"usage":{"input_tokens":2000,"output_tokens":300,"thinking_tokens":200,"cache_read_tokens":1500,"total_tokens":2300}}'
SH
chmod +x "$home/.local/bin/agy"

export HOME="$home"
export PATH="$home/.local/bin:$PATH"
export BIG_RED_AGENT_TEST_LOG="$log_root"
export GITHUB_TOKEN='github-available-to-full-peer'
export SSH_AUTH_SOCK='/tmp/ssh-agent-available-to-full-peer.sock'
export ANTHROPIC_API_KEY='must-be-unset-for-subscription-route'
export ANTHROPIC_BASE_URL='https://api-proxy.example.invalid'
export CLAUDE_CODE_USE_BEDROCK=1
export GEMINI_API_KEY='must-be-unset-for-subscription-route'
export GOOGLE_API_KEY='must-be-unset-for-subscription-route'
export GOOGLE_GENAI_USE_VERTEXAI=true
export OPENAI_API_KEY='must-be-unset-for-subscription-route'

(
  cd "$project"
  "$PEER" auth claude >/dev/null
)
grep -q '<auth><login>' "$log_root.claude"
grep -q '^anthropic_api=$' "$log_root.claude"
grep -q '^anthropic_base_url=$' "$log_root.claude"
grep -q '^claude_bedrock=$' "$log_root.claude"
grep -q '^gemini_api=$' "$log_root.claude"
grep -q '^openai_api=$' "$log_root.claude"

(
  cd "$project"
  "$PEER" auth antigravity >/dev/null
)
grep -q '^anthropic_api=$' "$log_root.antigravity"
grep -q '^google_api=$' "$log_root.antigravity"
grep -q '^google_genai_vertex=$' "$log_root.antigravity"
grep -q '^gemini_api=$' "$log_root.antigravity"
grep -q '^openai_api=$' "$log_root.antigravity"
rm "$project/peer-write.txt"

claude_review=$(cd "$project" && "$PEER" review claude -- 'review this change')
grep -q 'fake claude result' <<<"$claude_review"
grep -q "^cwd=$project$" "$log_root.claude"
grep -q "^home=$home$" "$log_root.claude"
grep -q '^github_token=github-available-to-full-peer$' "$log_root.claude"
grep -q '^ssh_auth_sock=/tmp/ssh-agent-available-to-full-peer.sock$' "$log_root.claude"
grep -q '^anthropic_api=$' "$log_root.claude"
grep -q '^anthropic_base_url=$' "$log_root.claude"
grep -q '^claude_bedrock=$' "$log_root.claude"
grep -q '^gemini_api=$' "$log_root.claude"
grep -q '^openai_api=$' "$log_root.claude"
grep -q '<--model><claude-opus-5>' "$log_root.claude"
grep -q '<--effort><high>' "$log_root.claude"
grep -q '<--dangerously-skip-permissions>' "$log_root.claude"
grep -q '<--output-format><json>' "$log_root.claude"
grep -q 'Act as an independent senior reviewer' "$log_root.claude"
if grep -q -- '--safe-mode' "$log_root.claude" ||
   grep -q -- '--tools' "$log_root.claude" ||
   grep -q -- '--permission-mode' "$log_root.claude"; then
  printf 'error: Claude invocation unexpectedly restricted peer capabilities\n' >&2
  exit 1
fi

claude_work=$(cd "$project" && printf '%s' 'implement this task' | "$PEER" work claude)
grep -q 'fake claude result' <<<"$claude_work"
grep -q 'Take ownership of this delegated coding task' "$log_root.claude"

antigravity_review=$(cd "$project" && "$PEER" review antigravity -- 'review the project')
grep -q 'fake antigravity result' <<<"$antigravity_review"
grep -q "^cwd=$project$" "$log_root.antigravity"
grep -q "^home=$home$" "$log_root.antigravity"
grep -q '^github_token=github-available-to-full-peer$' "$log_root.antigravity"
grep -q '^ssh_auth_sock=/tmp/ssh-agent-available-to-full-peer.sock$' "$log_root.antigravity"
grep -q '^anthropic_api=$' "$log_root.antigravity"
grep -q '^google_api=$' "$log_root.antigravity"
grep -q '^google_genai_vertex=$' "$log_root.antigravity"
grep -q '^gemini_api=$' "$log_root.antigravity"
grep -q '^openai_api=$' "$log_root.antigravity"
grep -q '<--model><gemini-3.7-flash-high>' "$log_root.antigravity"
grep -q '<--effort><high>' "$log_root.antigravity"
grep -q '<--dangerously-skip-permissions>' "$log_root.antigravity"
grep -q '<--output-format><json>' "$log_root.antigravity"
grep -q '<--print-timeout><60m>' "$log_root.antigravity"
if grep -q -- '--sandbox' "$log_root.antigravity"; then
  printf 'error: Antigravity invocation unexpectedly enabled a sandbox\n' >&2
  exit 1
fi
[[ -f "$project/peer-write.txt" ]]
rm "$project/peer-write.txt"

antigravity_run=$(cd "$project" && "$PEER" run antigravity -- 'do whatever is needed')
grep -q 'fake antigravity result' <<<"$antigravity_run"
[[ -f "$project/peer-write.txt" ]]
rm "$project/peer-write.txt"

ledger="$home/.local/state/big-red-agent-peer/usage.jsonl"
[[ -f "$ledger" ]]
[[ $(stat -c '%a' "$ledger") == 600 ]]
[[ $(wc -l < "$ledger") -eq 4 ]]
if grep -qE 'fake claude result|fake antigravity result|conversation_id|review this change' "$ledger"; then
  printf 'error: peer usage ledger leaked delegated content\n' >&2
  exit 1
fi

summary=$($PEER usage 168)
/usr/bin/python3 - "$summary" <<'PY'
import json
import sys
value = json.loads(sys.argv[1])
assert value["schema"] == "big-red-agent-peer-usage-summary/v1"
assert value["run_count"] == 4
assert value["billing_class"] == "subscription"
assert value["actual_marginal_cost_usd"] is None
rows = {(r["provider"], r["model"], r["effort"]): r for r in value["by_provider_model"]}
claude = rows[("claude", "claude-opus-5", "high")]
assert claude["runs"] == 2
assert claude["input_tokens"] == 2000
assert claude["cached_input_tokens"] == 1700
assert claude["cache_creation_input_tokens"] == 100
assert claude["output_tokens"] == 50
assert claude["total_tokens"] == 2050
assert claude["api_equivalent_estimate_usd"] == 2.5
antigravity = rows[("antigravity", "gemini-3.7-flash-high", "high")]
assert antigravity["runs"] == 2
assert antigravity["input_tokens"] == 4000
assert antigravity["cached_input_tokens"] == 3000
assert antigravity["output_tokens"] == 600
assert antigravity["reasoning_tokens"] == 400
assert antigravity["total_tokens"] == 4600
assert antigravity["api_equivalent_estimate_runs"] == 0
PY

mkdir -p "$temporary/outside"
if (cd "$temporary/outside" && "$PEER" run claude -- 'nope') >"$temporary/out" 2>"$temporary/err"; then
  printf 'error: peer runner accepted a directory outside a Git worktree\n' >&2
  exit 1
fi
grep -q 'must start inside a Git worktree' "$temporary/err"

printf 'big_red_agent_peer_tests=passed\n'

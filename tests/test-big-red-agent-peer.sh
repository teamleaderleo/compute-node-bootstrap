#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PEER="$ROOT/scripts/big-red-agent-peer"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
home="$temporary/home"
project="$temporary/project"
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
printf 'provider=claude\n'
printf 'cwd=%s\n' "$PWD"
printf 'home=%s\n' "$HOME"
printf 'github_token=%s\n' "${GITHUB_TOKEN:-}"
printf 'ssh_auth_sock=%s\n' "${SSH_AUTH_SOCK:-}"
printf 'anthropic_api=%s\n' "${ANTHROPIC_API_KEY:-}"
printf 'gemini_api=%s\n' "${GEMINI_API_KEY:-}"
printf 'openai_api=%s\n' "${OPENAI_API_KEY:-}"
printf 'claude_config=%s\n' "${CLAUDE_CONFIG_DIR:-}"
printf 'argv='
printf '<%s>' "$@"
printf '\n'
SH
chmod +x "$home/.local/bin/claude"

cat > "$home/.local/bin/agy" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'provider=antigravity\n'
printf 'cwd=%s\n' "$PWD"
printf 'home=%s\n' "$HOME"
printf 'github_token=%s\n' "${GITHUB_TOKEN:-}"
printf 'ssh_auth_sock=%s\n' "${SSH_AUTH_SOCK:-}"
printf 'anthropic_api=%s\n' "${ANTHROPIC_API_KEY:-}"
printf 'google_api=%s\n' "${GOOGLE_API_KEY:-}"
printf 'gemini_api=%s\n' "${GEMINI_API_KEY:-}"
printf 'openai_api=%s\n' "${OPENAI_API_KEY:-}"
printf 'argv='
printf '<%s>' "$@"
printf '\n'
printf 'peer touched live worktree\n' > peer-write.txt
SH
chmod +x "$home/.local/bin/agy"

export HOME="$home"
export PATH="$home/.local/bin:$PATH"
export GITHUB_TOKEN='github-available-to-full-peer'
export SSH_AUTH_SOCK='/tmp/ssh-agent-available-to-full-peer.sock'
export ANTHROPIC_API_KEY='must-be-unset-for-subscription-route'
export GEMINI_API_KEY='must-be-unset-for-subscription-route'
export GOOGLE_API_KEY='must-be-unset-for-subscription-route'
export OPENAI_API_KEY='must-be-unset-for-subscription-route'

claude_review=$(cd "$project" && "$PEER" review claude -- 'review this change')
grep -q '^provider=claude$' <<<"$claude_review"
grep -q "^cwd=$project$" <<<"$claude_review"
grep -q "^home=$home$" <<<"$claude_review"
grep -q '^github_token=github-available-to-full-peer$' <<<"$claude_review"
grep -q '^ssh_auth_sock=/tmp/ssh-agent-available-to-full-peer.sock$' <<<"$claude_review"
grep -q '^anthropic_api=$' <<<"$claude_review"
grep -q '^gemini_api=$' <<<"$claude_review"
grep -q '^openai_api=$' <<<"$claude_review"
grep -q '^claude_config=$' <<<"$claude_review"
grep -q '<--dangerously-skip-permissions>' <<<"$claude_review"
grep -q '<--effort><max>' <<<"$claude_review"
grep -q '<--output-format><json>' <<<"$claude_review"
! grep -q -- '--safe-mode' <<<"$claude_review"
! grep -q -- '--tools' <<<"$claude_review"
! grep -q -- '--permission-mode' <<<"$claude_review"
grep -q 'Act as an independent senior reviewer' <<<"$claude_review"

claude_work=$(cd "$project" && printf '%s' 'implement this task' | "$PEER" work claude)
grep -q '<--dangerously-skip-permissions>' <<<"$claude_work"
grep -q 'Take ownership of this delegated coding task' <<<"$claude_work"

antigravity_review=$(cd "$project" && "$PEER" review antigravity -- 'review the project')
grep -q '^provider=antigravity$' <<<"$antigravity_review"
grep -q "^cwd=$project$" <<<"$antigravity_review"
grep -q "^home=$home$" <<<"$antigravity_review"
grep -q '^github_token=github-available-to-full-peer$' <<<"$antigravity_review"
grep -q '^ssh_auth_sock=/tmp/ssh-agent-available-to-full-peer.sock$' <<<"$antigravity_review"
grep -q '^anthropic_api=$' <<<"$antigravity_review"
grep -q '^google_api=$' <<<"$antigravity_review"
grep -q '^gemini_api=$' <<<"$antigravity_review"
grep -q '^openai_api=$' <<<"$antigravity_review"
grep -q '<--dangerously-skip-permissions>' <<<"$antigravity_review"
grep -q '<--effort><high>' <<<"$antigravity_review"
grep -q '<--output-format><json>' <<<"$antigravity_review"
grep -q '<--print-timeout><60m>' <<<"$antigravity_review"
! grep -q -- '--sandbox' <<<"$antigravity_review"
[[ -f "$project/peer-write.txt" ]]
rm "$project/peer-write.txt"

antigravity_run=$(cd "$project" && "$PEER" run antigravity -- 'do whatever is needed')
grep -q '<--dangerously-skip-permissions>' <<<"$antigravity_run"
[[ -f "$project/peer-write.txt" ]]
rm "$project/peer-write.txt"

mkdir -p "$temporary/outside"
if (cd "$temporary/outside" && "$PEER" run claude -- 'nope') >"$temporary/out" 2>"$temporary/err"; then
  printf 'error: peer runner accepted a directory outside a Git worktree\n' >&2
  exit 1
fi
grep -q 'must start inside a Git worktree' "$temporary/err"

printf 'big_red_agent_peer_tests=passed\n'

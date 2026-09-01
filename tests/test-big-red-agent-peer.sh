#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PEER="$ROOT/scripts/big-red-agent-peer"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
home="$temporary/home"
project="$home/Projects/example"
mkdir -p "$home/.local/bin" "$project"

git -C "$project" init -q
git -C "$project" config user.name 'Peer Test'
git -C "$project" config user.email peer@example.invalid
printf 'base\n' > "$project/tracked.txt"
git -C "$project" add tracked.txt
git -C "$project" commit -qm base
printf 'working change\n' > "$project/tracked.txt"
printf 'untracked\n' > "$project/new.txt"

cat > "$home/.local/bin/claude" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
for secret in ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN GEMINI_API_KEY GOOGLE_API_KEY GOOGLE_APPLICATION_CREDENTIALS OPENAI_API_KEY GITHUB_TOKEN GH_TOKEN SSH_AUTH_SOCK AWS_ACCESS_KEY_ID; do
  if [[ -n ${!secret+x} ]]; then
    printf 'secret_present=%s\n' "$secret"
  fi
done
printf 'provider=claude\n'
printf 'cwd=%s\n' "$PWD"
printf 'home=%s\n' "$HOME"
printf 'claude_config=%s\n' "${CLAUDE_CONFIG_DIR:-}"
printf 'argv='
printf '<%s>' "$@"
printf '\n'
SH
chmod +x "$home/.local/bin/claude"

cat > "$home/.local/bin/agy" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
for secret in ANTHROPIC_API_KEY GEMINI_API_KEY GOOGLE_API_KEY GOOGLE_APPLICATION_CREDENTIALS OPENAI_API_KEY GITHUB_TOKEN GH_TOKEN SSH_AUTH_SOCK AWS_ACCESS_KEY_ID; do
  if [[ -n ${!secret+x} ]]; then
    printf 'secret_present=%s\n' "$secret"
  fi
done
printf 'provider=antigravity\n'
printf 'cwd=%s\n' "$PWD"
printf 'home=%s\n' "$HOME"
printf 'argv='
printf '<%s>' "$@"
printf '\n'
printf 'provider edit\n' > peer-write.txt
SH
chmod +x "$home/.local/bin/agy"

export HOME="$home"
export USER="$(id -un)"
export LOGNAME="$USER"
export GITHUB_TOKEN='must-not-cross-peer-boundary'
export ANTHROPIC_API_KEY='must-not-cross-peer-boundary'
export GEMINI_API_KEY='must-not-cross-peer-boundary'
export SSH_AUTH_SOCK='/tmp/must-not-cross-peer-boundary.sock'

claude_review=$(cd "$project" && "$PEER" review claude -- 'review this change')
grep -q '^provider=claude$' <<<"$claude_review"
grep -q "^cwd=$project$" <<<"$claude_review"
grep -q "^claude_config=$home/.local/state/big-red-agent-peer/claude$" <<<"$claude_review"
grep -q '<--safe-mode>' <<<"$claude_review"
grep -q '<--permission-mode><dontAsk>' <<<"$claude_review"
grep -q '<--tools><Read,Glob,Grep>' <<<"$claude_review"
! grep -q 'secret_present=' <<<"$claude_review"
! grep -q '<Bash>' <<<"$claude_review"
! grep -q '<Edit>' <<<"$claude_review"
! grep -q '<Write>' <<<"$claude_review"

claude_work=$(cd "$project" && printf '%s' 'edit this file' | "$PEER" work claude)
grep -q '<--permission-mode><acceptEdits>' <<<"$claude_work"
grep -q '<--tools><Read,Glob,Grep,Edit,Write>' <<<"$claude_work"
! grep -q '<Bash>' <<<"$claude_work"
! grep -q 'secret_present=' <<<"$claude_work"

antigravity_review=$(cd "$project" && "$PEER" review antigravity -- 'review the project')
grep -q '^provider=antigravity$' <<<"$antigravity_review"
grep -q "^home=$home/.local/state/big-red-agent-peer/antigravity-home$" <<<"$antigravity_review"
grep -q '<--output-format><json>' <<<"$antigravity_review"
grep -q '<--sandbox>' <<<"$antigravity_review"
grep -q '<--print-timeout><20m>' <<<"$antigravity_review"
! grep -q -- '--dangerously-skip-permissions' <<<"$antigravity_review"
! grep -q 'secret_present=' <<<"$antigravity_review"
review_cwd=$(sed -n 's/^cwd=//p' <<<"$antigravity_review")
[[ "$review_cwd" != "$project" ]]
[[ "$review_cwd" == "$home/.cache/big-red-agent-peer/review."* ]]
[[ ! -e "$review_cwd" ]]
[[ ! -e "$project/peer-write.txt" ]]

antigravity_work=$(cd "$project" && "$PEER" work antigravity -- 'edit the project')
grep -q "^cwd=$project$" <<<"$antigravity_work"
grep -q '<--sandbox>' <<<"$antigravity_work"
! grep -q 'secret_present=' <<<"$antigravity_work"
[[ -f "$project/peer-write.txt" ]]
rm "$project/peer-write.txt"

mkdir -p "$home/outside"
if (cd "$home/outside" && "$PEER" review claude -- 'nope') >"$temporary/out" 2>"$temporary/err"; then
  printf 'error: peer runner accepted a directory outside Projects\n' >&2
  exit 1
fi
grep -q 'must start inside a Git worktree' "$temporary/err"

[[ $(stat -c '%a' "$home/.local/state/big-red-agent-peer/claude") == 700 ]]
[[ $(stat -c '%a' "$home/.local/state/big-red-agent-peer/antigravity-home") == 700 ]]

printf 'big_red_agent_peer_tests=passed\n'

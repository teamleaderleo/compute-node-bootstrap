#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PEER="$ROOT/scripts/big-red-muse-peer"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
home="$temporary/home"
project="$temporary/project"
log="$temporary/opencode-log"
mkdir -p "$home/.local/bin" "$project"

git -C "$project" init -q
git -C "$project" config user.name 'Muse Peer Test'
git -C "$project" config user.email muse-peer@example.invalid
printf 'base\n' > "$project/tracked.txt"
git -C "$project" add tracked.txt
git -C "$project" commit -qm base

cat > "$home/.local/bin/opencode" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
log=${BIG_RED_MUSE_TEST_LOG:?}
if [[ ${1:-} == run && ${2:-} == --help ]]; then
  printf '%s\n' '--model --agent --format --dir --auto'
  exit 0
fi
if [[ ${1:-} == auth && ${2:-} == login ]]; then
  { printf 'argv='; printf '<%s>' "$@"; printf '\n'; } > "$log.auth"
  exit 0
fi
{
  printf 'cwd=%s\n' "$PWD"
  printf 'home=%s\n' "$HOME"
  printf 'github_token=%s\n' "${GITHUB_TOKEN:-}"
  printf 'argv='; printf '<%s>' "$@"; printf '\n'
} > "$log.run"
printf '%s\n' '{"type":"step_start","sessionID":"private-not-recorded","part":{"type":"step-start"}}'
printf '%s\n' '{"type":"text","sessionID":"private-not-recorded","part":{"type":"text","text":"fake Muse result"}}'
printf '%s\n' '{"type":"step_finish","sessionID":"private-not-recorded","part":{"type":"step-finish","reason":"tool-calls","cost":0,"tokens":{"input":1000,"output":100,"reasoning":50,"cache":{"read":970,"write":10}}}}'
printf '%s\n' '{"type":"step_finish","sessionID":"private-not-recorded","part":{"type":"step-finish","reason":"stop","cost":0,"tokens":{"input":500,"output":25,"reasoning":5,"cache":{"read":485,"write":0}}}}'
SH
chmod +x "$home/.local/bin/opencode"

export HOME="$home"
export PATH="$home/.local/bin:$PATH"
export BIG_RED_MUSE_TEST_LOG="$log"
export GITHUB_TOKEN='github-available-to-full-peer'

"$PEER" auth >/dev/null
grep -q '<auth><login><--provider><opencode>' "$log.auth"

review=$(cd "$project" && "$PEER" review -- 'review this change')
grep -q 'fake Muse result' <<<"$review"
grep -q "^cwd=$project$" "$log.run"
grep -q "^home=$home$" "$log.run"
grep -q '^github_token=github-available-to-full-peer$' "$log.run"
grep -q '<--dir>' "$log.run"
grep -q '<--model><opencode/muse-spark-1.3-contributor-free>' "$log.run"
grep -q '<--agent><build>' "$log.run"
grep -q '<--format><json>' "$log.run"
grep -q '<--auto>' "$log.run"
grep -q 'Act as an independent senior reviewer' "$log.run"

work=$(cd "$project" && printf '%s' 'implement this task' | "$PEER" work)
grep -q 'fake Muse result' <<<"$work"
grep -q 'Take ownership of this delegated coding task' "$log.run"

ledger="$home/.local/state/big-red-muse-peer/usage.jsonl"
[[ -f "$ledger" ]]
[[ $(stat -c '%a' "$ledger") == 600 ]]
[[ $(wc -l < "$ledger") -eq 2 ]]
if grep -qE 'fake Muse result|private-not-recorded|review this change' "$ledger"; then
  printf 'error: Muse usage ledger leaked delegated content\n' >&2
  exit 1
fi

summary=$($PEER usage 168)
/usr/bin/python3 - "$summary" <<'PY'
import json
import sys
value = json.loads(sys.argv[1])
assert value["schema"] == "big-red-muse-peer-usage-summary/v1"
assert value["run_count"] == 2
assert value["billing_class"] == "contributor-free"
assert value["actual_marginal_cost_usd"] == 0.0
assert value["input_tokens"] == 3000
assert value["cached_input_tokens"] == 2910
assert value["cache_creation_input_tokens"] == 20
assert value["output_tokens"] == 250
assert value["reasoning_tokens"] == 110
assert value["total_tokens"] == 3250
assert value["reported_cost_usd"] == 0.0
PY

mkdir -p "$temporary/outside"
if (cd "$temporary/outside" && "$PEER" run -- 'nope') >"$temporary/out" 2>"$temporary/err"; then
  printf 'error: Muse runner accepted a directory outside a Git worktree\n' >&2
  exit 1
fi
grep -q 'must start inside a Git worktree' "$temporary/err"

rm -f "$log.run"
if BIG_RED_MUSE_MODEL='opencode/some-other-paid-model' "$PEER" run -- 'paid override' >"$temporary/out" 2>"$temporary/err"; then
  printf 'error: Muse runner accepted a non-pinned BIG_RED_MUSE_MODEL\n' >&2
  exit 1
fi
grep -q 'BIG_RED_MUSE_MODEL must be opencode/muse-spark-1.3-contributor-free' "$temporary/err"
[[ ! -e "$log.run" ]]

identical=$(cd "$project" && BIG_RED_MUSE_MODEL='opencode/muse-spark-1.3-contributor-free' "$PEER" run -- 'pinned override')
grep -q 'fake Muse result' <<<"$identical"
grep -q '<--model><opencode/muse-spark-1.3-contributor-free>' "$log.run"

BIG_RED_MUSE_MODEL='opencode/some-other-paid-model' "$PEER" usage 168 >/dev/null

printf 'big_red_muse_peer_tests=passed\n'

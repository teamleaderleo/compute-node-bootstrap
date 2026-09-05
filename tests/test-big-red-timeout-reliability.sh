#!/usr/bin/env bash
# Regression: a provider that ignores TERM must not defeat BIG_RED_AGENT_TIMEOUT.
# The wrapper must deliver TERM, then KILL via `timeout -k`, bound the wait,
# exit 137 after forced KILL, and still record a content-free usage receipt. Cleanup must be
# scoped to the invocation (an unrelated sleep must survive).
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MUSE_PEER="$ROOT/scripts/big-red-muse-peer"
AGENT_PEER="$ROOT/scripts/big-red-agent-peer"

temporary=$(mktemp -d)
unrelated=''
cleanup() {
  if [[ -n "$unrelated" ]]; then
    kill "$unrelated" 2>/dev/null || true
    wait "$unrelated" 2>/dev/null || true
  fi
  rm -rf "$temporary"
}
trap cleanup EXIT
test_home="$temporary/home"
project="$temporary/project"
mkdir -p "$test_home/.local/bin" "$project"

git -C "$project" init -q
git -C "$project" config user.name 'Timeout Test'
git -C "$project" config user.email timeout@example.invalid
printf 'base\n' > "$project/tracked.txt"
git -C "$project" add tracked.txt
git -C "$project" commit -qm base

# Fake provider: mode via env. "hang" ignores TERM and sleeps long;
# "ok" emits one happy-path JSON line immediately.
make_fake() {
  local name=$1 json_line=$2 help_response=$3
  cat > "$test_home/.local/bin/$name" <<SH
#!/usr/bin/env bash
set -euo pipefail
marker=\${BIG_RED_TIMEOUT_MARKER:-/dev/null}
if [[ "\${1:-}" == "run" && "\${2:-}" == "--help" ]]; then
  printf '%s\\n' '$help_response'
  exit 0
fi
if [[ "\${BIG_RED_TIMEOUT_TEST_MODE:-hang}" == "ok" ]]; then
  printf '%s\\n' '$json_line'
  exit 0
fi
# A single process avoids orphaning a fake sleep when timeout sends KILL.
exec python3 - "\$marker" <<'FAKE_PY'
import signal
import sys
import time

def term(_signum, _frame):
    with open(sys.argv[1], "a") as marker_file:
        marker_file.write("TERM\\n")

signal.signal(signal.SIGTERM, term)
time.sleep(8)
FAKE_PY
SH
  chmod +x "$test_home/.local/bin/$name"
}

make_fake opencode '{"type":"text","part":{"type":"text","text":"muse ok"}}' '--model --agent --format --dir --auto'
make_fake claude '{"subtype":"success","result":"claude ok","usage":{"input_tokens":1,"output_tokens":1}}' 'x'
make_fake agy '{"status":"SUCCESS","response":"agy ok","usage":{"input_tokens":1,"output_tokens":1,"total_tokens":2}}' 'x'

export HOME="$test_home"
export PATH="$test_home/.local/bin:$PATH"
export BIG_RED_AGENT_TIMEOUT=2s
export BIG_RED_AGENT_KILL_AFTER=1s

check_hang() {
  local label=$1 marker=$2 ledger=$3
  shift 3
  rm -f "$marker"
  export BIG_RED_TIMEOUT_MARKER="$marker"
  export BIG_RED_TIMEOUT_TEST_MODE=hang
  sleep 60 &
  unrelated=$!
  set +e
  start_s=$SECONDS
  (cd "$project" && /usr/bin/timeout --foreground -k 1s 10s "$@" >"$temporary/$label.out" 2>"$temporary/$label.err")
  status=$?
  set -e
  elapsed_s=$((SECONDS - start_s))
  if ! kill -0 "$unrelated" 2>/dev/null; then
    printf 'error: %s killed an unrelated process\n' "$label" >&2
    kill "$unrelated" 2>/dev/null || true
    return 1
  fi
  kill "$unrelated" 2>/dev/null || true
  wait "$unrelated" 2>/dev/null || true
  unrelated=''
  [[ $status -eq 137 ]] || { printf 'error: %s exit=%s want 137 (KILL-forced)\n' "$label" "$status" >&2; return 1; }
  [[ $elapsed_s -lt 7 ]] || { printf 'error: %s waited %ss, deadline escaped\n' "$label" "$elapsed_s" >&2; return 1; }
  grep -q TERM "$marker" || { printf 'error: %s never delivered TERM before KILL\n' "$label" >&2; return 1; }
  grep -q "\"exit_code\":$status" "$ledger" || { printf 'error: %s ledger missing exit_code %s\n' "$label" "$status" >&2; return 1; }
  if grep -qE 'muse ok|claude ok|agy ok|TERM-test' "$ledger"; then
    printf 'error: %s ledger leaked content\n' "$label" >&2
    return 1
  fi
  printf '%s deadline enforced in %ss, exit %s\n' "$label" "$elapsed_s" "$status"
}

muse_marker="$temporary/muse-term"
muse_ledger="$test_home/.local/state/big-red-muse-peer/usage.jsonl"
rm -f "$muse_ledger"
check_hang muse "$muse_marker" "$muse_ledger" "$MUSE_PEER" run -- 'TERM-test prompt'
export BIG_RED_TIMEOUT_TEST_MODE=ok
muse_out=$(cd "$project" && "$MUSE_PEER" run -- 'hello')
grep -q 'muse ok' <<<"$muse_out" || { printf 'error: muse happy path lost result\n' >&2; exit 1; }
[[ $(wc -l < "$muse_ledger") -eq 2 ]] || { printf 'error: muse ledger should have hang+ok rows\n' >&2; exit 1; }

claude_marker="$temporary/claude-term"
agent_ledger="$test_home/.local/state/big-red-agent-peer/usage.jsonl"
rm -f "$agent_ledger"
check_hang claude "$claude_marker" "$agent_ledger" "$AGENT_PEER" run claude -- 'TERM-test prompt'
export BIG_RED_TIMEOUT_TEST_MODE=ok
claude_out=$(cd "$project" && "$AGENT_PEER" run claude -- 'hello')
grep -q 'claude ok' <<<"$claude_out" || { printf 'error: claude happy path lost result\n' >&2; exit 1; }

agy_marker="$temporary/agy-term"
rm -f "$agent_ledger"
check_hang antigravity "$agy_marker" "$agent_ledger" "$AGENT_PEER" run antigravity -- 'TERM-test prompt'
export BIG_RED_TIMEOUT_TEST_MODE=ok
agy_out=$(cd "$project" && "$AGENT_PEER" run antigravity -- 'hello')
grep -q 'agy ok' <<<"$agy_out" || { printf 'error: antigravity happy path lost result\n' >&2; exit 1; }

printf 'big_red_timeout_reliability_tests=passed\n'

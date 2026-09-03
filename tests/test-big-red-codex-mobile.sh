#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LAUNCHER="$ROOT/scripts/big-red-codex-mobile"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
home="$temporary/home"
fakebin="$temporary/fakebin"
log="$temporary/tmux.log"
mkdir -p "$home/Projects/glaeda" "$fakebin"

cat > "$fakebin/clear" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat > "$fakebin/git" <<'SH'
#!/usr/bin/env bash
[[ ${1:-} == -C && ${3:-} == rev-parse && ${4:-} == --is-inside-work-tree ]]
SH
cat > "$fakebin/tmux" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> '$log'
SH
cat > "$fakebin/sleep" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$fakebin"/*

run_launcher() {
  env HOME="$home" PATH="$fakebin:/usr/bin:/bin" "$LAUNCHER"
}

printf '1\nglaeda\nq\n' | run_launcher >/dev/null
grep -q -- 'new-session -A -s codex-muse-xhigh-glaeda' "$log"
grep -q -- 'codex -p muse-xhigh' "$log"

: > "$log"
printf '2\nglaeda\nq\n' | run_launcher >/dev/null
grep -q -- 'codex -p muse-high' "$log"

: > "$log"
printf '3\nglaeda\nq\n' | run_launcher >/dev/null
grep -q -- 'new-session -A -s codex-sol-glaeda' "$log"
grep -qE -- 'glaeda codex$' "$log"
if grep -q -- ' -p ' "$log"; then
  printf 'Sol must use the unchanged unprofiled Codex default\n' >&2
  exit 1
fi

: > "$log"
printf '1\n../escape\nglaeda\nq\n' | run_launcher >/dev/null
grep -q -- 'codex -p muse-xhigh' "$log"

printf 'ok: Codex mobile launcher selects only the exact supported profiles\n'

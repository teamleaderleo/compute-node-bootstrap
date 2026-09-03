#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="$ROOT/scripts/install-big-red-muse-peer"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
home="$temporary/home"
fakebin="$temporary/fakebin"
mkdir -p "$home" "$fakebin"

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

cat > "$fakebin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
output=
while (($#)); do
  case "$1" in
    --output) output=$2; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$output" ]]
cat > "$output" <<'INNER'
#!/usr/bin/env bash
set -euo pipefail
: "${XDG_BIN_DIR:?}"
mkdir -p "$XDG_BIN_DIR"
cat > "$XDG_BIN_DIR/opencode" <<'OC'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --version) printf 'opencode fake 1.0\n' ;;
  run)
    if [[ ${2:-} == --help ]]; then
      printf '%s\n' '--model --agent --format --dir --auto'
    else
      exit 2
    fi
    ;;
  auth)
    if [[ ${2:-} == login && ${3:-} == --help ]]; then
      printf '%s\n' '--provider --method'
    else
      exit 2
    fi
    ;;
  *) exit 2 ;;
esac
OC
chmod +x "$XDG_BIN_DIR/opencode"
INNER
chmod +x "$output"
SH
chmod +x "$fakebin/curl"

export PATH="$fakebin:$PATH"

plan=$($INSTALLER --plan --operator-user muse-test)
grep -q '^operator_user=muse-test$' <<<"$plan"
grep -q '^opencode_installer=https://opencode.ai/install$' <<<"$plan"
grep -q '^opencode_launcher_relative=.local/bin/opencode$' <<<"$plan"
grep -q '^muse_model=opencode/muse-spark-1.3-contributor-free$' <<<"$plan"
grep -q '^provider_authentication=separate_interactive_step$' <<<"$plan"

$INSTALLER --operator-user muse-test >"$temporary/apply.out"
grep -q '^opencode_install=verified$' "$temporary/apply.out"
grep -q '^muse_full_delegate=available$' "$temporary/apply.out"
[[ -x "$home/.local/bin/opencode" ]]
[[ -x "$home/.local/bin/big-red-muse-peer" ]]

$INSTALLER --verify-only --operator-user muse-test >"$temporary/verify.out"
grep -q '^opencode_version=opencode fake 1.0$' "$temporary/verify.out"
grep -q '^authentication_status=not_inspected$' "$temporary/verify.out"

printf 'install_big_red_muse_peer_tests=passed\n'

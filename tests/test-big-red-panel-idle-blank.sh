#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script=${repo_root}/scripts/big-red-panel-idle-blank
installer=${repo_root}/scripts/install-big-red-panel-idle-blank
tmp_dir=$(mktemp -d)
trap 'rm -rf "${tmp_dir}"' EXIT

bash -n "${script}"
bash -n "${installer}"

cat >"${tmp_dir}/gdbus" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${FAKE_GDBUS_LOG}"
case "$*" in
  *IsInhibited*) printf '(%s,)\n' "${FAKE_INHIBITED:-false}" ;;
  *GetIdletime*) printf '(uint64 %s,)\n' "${FAKE_IDLE_MS:-0}" ;;
  *Properties.Get*) printf '(<%s>,)\n' "${FAKE_POWER_MODE:-0}" ;;
  *Properties.Set*) printf '()\n' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "${tmp_dir}/gdbus"

run_case() {
  : >"${tmp_dir}/calls"
  env \
    PATH="${tmp_dir}:${PATH}" \
    FAKE_GDBUS_LOG="${tmp_dir}/calls" \
    FAKE_IDLE_MS="$1" \
    FAKE_POWER_MODE="$2" \
    FAKE_INHIBITED="$3" \
    "${script}"
}

run_case 599999 0 false
if grep -q 'Properties.Set' "${tmp_dir}/calls"; then
  printf 'Panel was blanked before the idle threshold.\n' >&2
  exit 1
fi

run_case 600000 0 false
grep -q "Properties.Set.*PowerSaveMode <3>" "${tmp_dir}/calls"

run_case 900000 3 false
if grep -q 'Properties.Set' "${tmp_dir}/calls"; then
  printf 'An already blank panel was written again.\n' >&2
  exit 1
fi

run_case 900000 0 true
if grep -q 'GetIdletime\|Properties.Set' "${tmp_dir}/calls"; then
  printf 'A GNOME-inhibited session was inspected or blanked.\n' >&2
  exit 1
fi

if grep -Eq 'xdotool|ydotool|uinput' "${script}"; then
  printf 'The fallback must not contain an input-injection path.\n' >&2
  exit 1
fi

grep -Fxq 'OnUnitActiveSec=1min' \
  "${repo_root}/systemd/big-red-panel-idle-blank.timer"
grep -Fxq 'ExecStart=/usr/local/sbin/big-red-panel-idle-blank' \
  "${repo_root}/systemd/big-red-panel-idle-blank.service"

printf 'Big Red panel idle blank fallback verified.\n'

#!/bin/sh
set -eu

repository_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
diagnostic=$repository_root/scripts/big-red-connectivity-check
test_root=$(mktemp -d /tmp/big-red-connectivity-test.XXXXXX)
pid_file=$test_root/timeout-pids

cleanup() {
    if [ -r "$pid_file" ]; then
        while read -r owned_pid _; do
            case "$owned_pid" in
                ''|*[!0-9]*) continue ;;
            esac
            if kill -0 "$owned_pid" 2>/dev/null; then
                kill -KILL "$owned_pid" 2>/dev/null || true
            fi
        done <"$pid_file"
    fi
    if [ -d "$test_root" ]; then
        rm -r -- "$test_root"
    fi
}
trap cleanup EXIT HUP INT TERM

BIG_RED_CONNECTIVITY_CHECK_FUNCTIONS_ONLY=1
export BIG_RED_CONNECTIVITY_CHECK_FUNCTIONS_ONLY
# shellcheck source=../scripts/big-red-connectivity-check
# shellcheck disable=SC1091
. "$diagnostic"
unset BIG_RED_CONNECTIVITY_CHECK_FUNCTIONS_ONLY

timeout_bin=$test_root/timeout-bin
mkdir "$timeout_bin"
cat >"$timeout_bin/nvme" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$timeout_bin/sudo" <<'EOF'
#!/bin/sh
pgid=$(ps -o pgid= -p "$$" | tr -d ' ')
printf '%s %s\n' "$$" "$pgid" >"$SMART_TEST_PID_FILE"
trap '' TERM
while :; do
    sleep 30
done
EOF
chmod 0755 "$timeout_bin/nvme" "$timeout_bin/sudo"

SMART_TEST_PID_FILE=$pid_file
export SMART_TEST_PID_FILE
original_path=$PATH
PATH=$timeout_bin:/usr/bin:/bin
export PATH
started=$(date +%s)
timeout_output=$(nvme_health_summary /dev/nvme0)
elapsed=$(($(date +%s) - started))
PATH=$original_path
export PATH
unset SMART_TEST_PID_FILE

[ "$timeout_output" = 'nvme_smart=unavailable' ] || {
    printf 'timeout case mislabeled SMART: %s\n' "$timeout_output" >&2
    exit 1
}
[ "$elapsed" -ge 5 ] && [ "$elapsed" -le 8 ] || {
    printf 'timeout case escaped bound: %s seconds\n' "$elapsed" >&2
    exit 1
}
read -r timed_pid timed_pgid <"$pid_file"
if kill -0 "$timed_pid" 2>/dev/null; then
    printf 'timeout command survived: %s\n' "$timed_pid" >&2
    exit 1
fi
if /usr/bin/kill -0 -- "-$timed_pgid" 2>/dev/null; then
    printf 'timeout process group survived: %s\n' "$timed_pgid" >&2
    exit 1
fi

projection_bin=$test_root/projection-bin
projection_count=$test_root/projection-count
mkdir "$projection_bin"
cat >"$projection_bin/nvme" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$projection_bin/sudo" <<'EOF'
#!/bin/sh
printf '%s\n' '{"critical_warning":0,"avail_spare":100,"spare_thresh":10,"percent_used":0,"media_errors":0,"num_err_log_entries":0,"unsafe_shutdowns":5,"warning_temp_time":0,"critical_comp_time":0}'
EOF
cat >"$projection_bin/jq" <<'EOF'
#!/bin/sh
count=0
if [ -r "$SMART_TEST_JQ_COUNT" ]; then
    count=$(cat "$SMART_TEST_JQ_COUNT")
fi
count=$((count + 1))
printf '%s\n' "$count" >"$SMART_TEST_JQ_COUNT"
exit 1
EOF
chmod 0755 "$projection_bin/nvme" "$projection_bin/sudo" "$projection_bin/jq"

SMART_TEST_JQ_COUNT=$projection_count
export SMART_TEST_JQ_COUNT
PATH=$projection_bin:/usr/bin:/bin
export PATH
projection_output=$(nvme_health_summary /dev/nvme0)
PATH=$original_path
export PATH
unset SMART_TEST_JQ_COUNT

[ "$projection_output" = 'nvme_smart=unavailable' ] || {
    printf 'projection failure mislabeled SMART: %s\n' "$projection_output" >&2
    exit 1
}
[ "$(cat "$projection_count")" = 1 ] || {
    printf 'SMART projection was not one transaction\n' >&2
    exit 1
}

printf 'big-red connectivity SMART regressions: passed\n'

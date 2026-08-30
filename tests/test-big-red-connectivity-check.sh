#!/bin/sh
set -eu

repository_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
diagnostic=$repository_root/scripts/big-red-connectivity-check
test_root=$(mktemp -d /tmp/big-red-connectivity-test.XXXXXX)
pid_file=$test_root/timeout-pids
interrupt_pid_file=$test_root/interruption-pids
substitution_pid_file=$test_root/substitution-pids
race_pid_file=$test_root/race-probe-pids
race_setsid_file=$test_root/race-setsid-pid
interrupt_driver_pid=
substitution_driver_pid=
race_setsid_pid=

cleanup() {
    if [ -n "$interrupt_driver_pid" ] &&
        kill -0 "$interrupt_driver_pid" 2>/dev/null; then
        kill -KILL "$interrupt_driver_pid" 2>/dev/null || true
    fi
    if [ -n "$substitution_driver_pid" ] &&
        kill -0 "$substitution_driver_pid" 2>/dev/null; then
        kill -KILL "$substitution_driver_pid" 2>/dev/null || true
    fi
    if [ -n "$race_setsid_pid" ] &&
        kill -0 "$race_setsid_pid" 2>/dev/null; then
        kill -KILL "$race_setsid_pid" 2>/dev/null || true
    fi
    for owned_pid_file in \
        "$pid_file" \
        "$interrupt_pid_file" \
        "$substitution_pid_file" \
        "$race_pid_file"; do
        [ -r "$owned_pid_file" ] || continue
        while read -r owned_leader owned_child owned_pgid; do
            for owned_pid in "$owned_leader" "$owned_child"; do
                case "$owned_pid" in
                    ''|*[!0-9]*) continue ;;
                esac
                if kill -0 "$owned_pid" 2>/dev/null; then
                    kill -KILL "$owned_pid" 2>/dev/null || true
                fi
            done
            case "$owned_pgid" in
                ''|*[!0-9]*) continue ;;
            esac
            /usr/bin/kill -KILL -- "-$owned_pgid" 2>/dev/null || true
        done <"$owned_pid_file"
    done
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
(
    trap '' TERM
    while :; do
        sleep 30
    done
) &
child=$!
printf '%s %s %s\n' "$$" "$child" "$pgid" >"$SMART_TEST_PID_FILE"
trap 'exit 0' TERM
wait "$child"
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
read -r timed_pid timed_child timed_pgid <"$pid_file"
for owned_pid in "$timed_pid" "$timed_child"; do
    if kill -0 "$owned_pid" 2>/dev/null; then
        printf 'timeout command survived: %s\n' "$owned_pid" >&2
        exit 1
    fi
done
if /usr/bin/kill -0 -- "-$timed_pgid" 2>/dev/null; then
    printf 'timeout process group survived: %s\n' "$timed_pgid" >&2
    exit 1
fi

interrupt_tmp=$test_root/interruption-tmp
mkdir "$interrupt_tmp"
# shellcheck disable=SC2016 # $1 belongs to the isolated child shell
env \
    PATH="$timeout_bin:/usr/bin:/bin" \
    TMPDIR="$interrupt_tmp" \
    SMART_TEST_PID_FILE="$interrupt_pid_file" \
    BIG_RED_CONNECTIVITY_CHECK_FUNCTIONS_ONLY=1 \
    sh -c '. "$1"; nvme_health_summary /dev/nvme0 >/dev/null' \
    sh "$diagnostic" 2>"$test_root/interruption-stderr" &
interrupt_driver_pid=$!
attempts=0
while [ ! -r "$interrupt_pid_file" ] && [ "$attempts" -lt 30 ]; do
    sleep 0.1
    attempts=$((attempts + 1))
done
[ -r "$interrupt_pid_file" ] || {
    printf 'interrupted SMART probe never launched\n' >&2
    exit 1
}
/usr/bin/kill -TERM "$interrupt_driver_pid"
attempts=0
while kill -0 "$interrupt_driver_pid" 2>/dev/null &&
    [ "$attempts" -lt 30 ]; do
    sleep 0.1
    attempts=$((attempts + 1))
done
if kill -0 "$interrupt_driver_pid" 2>/dev/null; then
    printf 'PID-targeted caller did not exit\n' >&2
    exit 1
fi
wait "$interrupt_driver_pid" 2>/dev/null || true
interrupt_driver_pid=
read -r interrupted_pid interrupted_child interrupted_pgid \
    <"$interrupt_pid_file"
attempts=0
while [ "$attempts" -lt 30 ]; do
    if ! kill -0 "$interrupted_pid" 2>/dev/null &&
        ! kill -0 "$interrupted_child" 2>/dev/null &&
        ! /usr/bin/kill -0 -- "-$interrupted_pgid" 2>/dev/null; then
        break
    fi
    sleep 0.1
    attempts=$((attempts + 1))
done
for owned_pid in "$interrupted_pid" "$interrupted_child"; do
    if kill -0 "$owned_pid" 2>/dev/null; then
        printf 'interrupted command survived: %s\n' "$owned_pid" >&2
        exit 1
    fi
done
if /usr/bin/kill -0 -- "-$interrupted_pgid" 2>/dev/null; then
    printf 'interrupted process group survived: %s\n' \
        "$interrupted_pgid" >&2
    exit 1
fi
attempts=0
while find "$interrupt_tmp" -mindepth 1 -print -quit | grep -q . &&
    [ "$attempts" -lt 30 ]; do
    sleep 0.1
    attempts=$((attempts + 1))
done
if find "$interrupt_tmp" -mindepth 1 -print -quit | grep -q .; then
    printf 'interrupted SMART probe left a temporary file\n' >&2
    exit 1
fi

substitution_tmp=$test_root/substitution-tmp
mkdir "$substitution_tmp"
# A command substitution inserts another shell between the function subshell
# and its invoker. Killing the outer invoking shell must still tear down the
# owned probe group and private output.
# shellcheck disable=SC2016 # $1 belongs to the isolated child shell
env \
    PATH="$timeout_bin:/usr/bin:/bin" \
    TMPDIR="$substitution_tmp" \
    SMART_TEST_PID_FILE="$substitution_pid_file" \
    BIG_RED_CONNECTIVITY_CHECK_FUNCTIONS_ONLY=1 \
    sh -c '. "$1"; result=$(nvme_health_summary /dev/nvme0); printf "%s\n" "$result"' \
    sh "$diagnostic" 2>"$test_root/substitution-stderr" &
substitution_driver_pid=$!
attempts=0
while [ ! -r "$substitution_pid_file" ] && [ "$attempts" -lt 30 ]; do
    sleep 0.1
    attempts=$((attempts + 1))
done
[ -r "$substitution_pid_file" ] || {
    printf 'command-substitution SMART probe never launched\n' >&2
    exit 1
}
/usr/bin/kill -TERM "$substitution_driver_pid"
attempts=0
while kill -0 "$substitution_driver_pid" 2>/dev/null &&
    [ "$attempts" -lt 30 ]; do
    sleep 0.1
    attempts=$((attempts + 1))
done
if kill -0 "$substitution_driver_pid" 2>/dev/null; then
    printf 'command-substitution caller did not exit\n' >&2
    exit 1
fi
wait "$substitution_driver_pid" 2>/dev/null || true
substitution_driver_pid=
read -r substitution_pid substitution_child substitution_pgid \
    <"$substitution_pid_file"
attempts=0
while [ "$attempts" -lt 30 ]; do
    if ! kill -0 "$substitution_pid" 2>/dev/null &&
        ! kill -0 "$substitution_child" 2>/dev/null &&
        ! /usr/bin/kill -0 -- "-$substitution_pgid" 2>/dev/null; then
        break
    fi
    sleep 0.1
    attempts=$((attempts + 1))
done
for owned_pid in "$substitution_pid" "$substitution_child"; do
    if kill -0 "$owned_pid" 2>/dev/null; then
        printf 'command-substitution probe survived: %s\n' "$owned_pid" >&2
        exit 1
    fi
done
if /usr/bin/kill -0 -- "-$substitution_pgid" 2>/dev/null; then
    printf 'command-substitution process group survived: %s\n' \
        "$substitution_pgid" >&2
    exit 1
fi
attempts=0
while find "$substitution_tmp" -mindepth 1 -print -quit | grep -q . &&
    [ "$attempts" -lt 30 ]; do
    sleep 0.1
    attempts=$((attempts + 1))
done
if find "$substitution_tmp" -mindepth 1 -print -quit | grep -q .; then
    printf 'command-substitution interruption left a temporary file\n' >&2
    exit 1
fi

race_bin=$test_root/race-bin
race_tmp=$test_root/race-tmp
mkdir "$race_bin" "$race_tmp"
cat >"$race_bin/nvme" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$race_bin/setsid" <<'EOF'
#!/bin/sh
printf '%s\n' "$$" >"$SMART_TEST_SETSID_PID_FILE"
trap '' TERM
sleep 2
exec /usr/bin/setsid "$@"
EOF
cat >"$race_bin/sudo" <<'EOF'
#!/bin/sh
pgid=$(ps -o pgid= -p "$$" | tr -d ' ')
(
    trap '' TERM
    while :; do
        sleep 30
    done
) &
child=$!
printf '%s %s %s\n' "$$" "$child" "$pgid" >"$SMART_TEST_PID_FILE"
trap 'exit 0' TERM
wait "$child"
EOF
chmod 0755 "$race_bin/nvme" "$race_bin/setsid" "$race_bin/sudo"

# shellcheck disable=SC2016 # $1 belongs to the isolated child shell
env \
    PATH="$race_bin:/usr/bin:/bin" \
    TMPDIR="$race_tmp" \
    SMART_TEST_PID_FILE="$race_pid_file" \
    SMART_TEST_SETSID_PID_FILE="$race_setsid_file" \
    BIG_RED_CONNECTIVITY_CHECK_FUNCTIONS_ONLY=1 \
    sh -c '. "$1"; nvme_health_summary /dev/nvme0 >/dev/null' \
    sh "$diagnostic" 2>"$test_root/race-stderr" &
interrupt_driver_pid=$!
attempts=0
while [ ! -r "$race_setsid_file" ] && [ "$attempts" -lt 30 ]; do
    sleep 0.1
    attempts=$((attempts + 1))
done
[ -r "$race_setsid_file" ] || {
    printf 'delayed setsid wrapper never launched\n' >&2
    exit 1
}
read -r race_setsid_pid <"$race_setsid_file"
/usr/bin/kill -TERM "$interrupt_driver_pid"
attempts=0
while kill -0 "$interrupt_driver_pid" 2>/dev/null &&
    [ "$attempts" -lt 30 ]; do
    sleep 0.1
    attempts=$((attempts + 1))
done
if kill -0 "$interrupt_driver_pid" 2>/dev/null; then
    printf 'pre-PGID caller did not exit\n' >&2
    exit 1
fi
wait "$interrupt_driver_pid" 2>/dev/null || true
interrupt_driver_pid=
attempts=0
while kill -0 "$race_setsid_pid" 2>/dev/null &&
    [ "$attempts" -lt 30 ]; do
    sleep 0.1
    attempts=$((attempts + 1))
done
if kill -0 "$race_setsid_pid" 2>/dev/null; then
    printf 'pre-PGID setsid wrapper survived: %s\n' "$race_setsid_pid" >&2
    exit 1
fi
race_setsid_pid=
if [ -e "$race_pid_file" ]; then
    printf 'pre-PGID race launched the privileged probe\n' >&2
    exit 1
fi
attempts=0
while find "$race_tmp" -mindepth 1 -print -quit | grep -q . &&
    [ "$attempts" -lt 30 ]; do
    sleep 0.1
    attempts=$((attempts + 1))
done
if find "$race_tmp" -mindepth 1 -print -quit | grep -q .; then
    printf 'pre-PGID interruption left a temporary file\n' >&2
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
trap_before=$(trap)
nvme_health_summary /dev/nvme0 >"$test_root/direct-smart-output"
trap_after=$(trap)
[ "$trap_before" = "$trap_after" ] || {
    printf 'SMART probe replaced caller traps\n' >&2
    exit 1
}
[ "$(cat "$test_root/direct-smart-output")" = 'nvme_smart=unavailable' ] || {
    printf 'direct SMART projection failure was mislabeled\n' >&2
    exit 1
}
: >"$projection_count"
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

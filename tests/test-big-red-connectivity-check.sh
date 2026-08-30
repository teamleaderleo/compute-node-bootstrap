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

grep -q 'router_oom_kills_observed_log=' "$diagnostic"
grep -q 'router_latest_oom_age_seconds_observed_log=' "$diagnostic"
if grep -q 'router_oom_kills_current_boot=' "$diagnostic"; then
    printf 'Beryl OOM count still claims boot-complete retention\n' >&2
    exit 1
fi

cat >"$test_root/meminfo" <<'EOF'
MemTotal:       32768000 kB
MemAvailable:   24576000 kB
SwapTotal:       8388608 kB
SwapFree:        5242880 kB
EOF
cat >"$test_root/pressure-memory" <<'EOF'
some avg10=1.25 avg60=0.50 avg300=0.20 total=1234
full avg10=0.03 avg60=0.01 avg300=0.00 total=56
EOF
memory_output=$(memory_capacity_summary \
    "$test_root/meminfo" "$test_root/pressure-memory")
expected_memory_output='memory_available_kib=24576000
swap_total_kib=8388608
swap_used_kib=3145728
memory_psi_some_avg10=1.25
memory_psi_full_avg10=0.03'
[ "$memory_output" = "$expected_memory_output" ] || {
    printf 'memory capacity projection mismatch:\n%s\n' "$memory_output" >&2
    exit 1
}

cat >"$test_root/meminfo-invalid-swap" <<'EOF'
MemAvailable:   1024 kB
SwapTotal:      1024 kB
SwapFree:       2048 kB
EOF
invalid_swap_output=$(memory_capacity_summary \
    "$test_root/meminfo-invalid-swap" "$test_root/missing-pressure")
expected_invalid_swap_output='memory_available_kib=1024
swap_total_kib=1024
swap_used_kib=unavailable
memory_psi_some_avg10=unavailable
memory_psi_full_avg10=unavailable'
[ "$invalid_swap_output" = "$expected_invalid_swap_output" ] || {
    printf 'invalid memory evidence did not fail closed:\n%s\n' \
        "$invalid_swap_output" >&2
    exit 1
}

capacity_bin=$test_root/capacity-bin
mkdir "$capacity_bin"
cat >"$capacity_bin/findmnt" <<'EOF'
#!/bin/sh
printf 'tmpfs\n'
EOF
cat >"$capacity_bin/df" <<'EOF'
#!/bin/sh
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
printf 'tmpfs 16384000 286720 16097280 2%% /tmp\n'
EOF
chmod 0755 "$capacity_bin/findmnt" "$capacity_bin/df"
filesystem_output=$(filesystem_capacity_summary /tmp tmp \
    "$capacity_bin/findmnt" "$capacity_bin/df")
expected_filesystem_output='tmp_filesystem_type=tmpfs
tmp_total_kib=16384000
tmp_used_kib=286720
tmp_used_percent=2%'
[ "$filesystem_output" = "$expected_filesystem_output" ] || {
    printf 'filesystem capacity projection mismatch:\n%s\n' \
        "$filesystem_output" >&2
    exit 1
}
cat >"$capacity_bin/df" <<'EOF'
#!/bin/sh
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
printf 'tmpfs private-name invalid 16097280 nope /tmp\n'
EOF
chmod 0755 "$capacity_bin/df"
invalid_filesystem_output=$(filesystem_capacity_summary /tmp tmp \
    "$capacity_bin/findmnt" "$capacity_bin/df")
expected_invalid_filesystem_output='tmp_filesystem_type=tmpfs
tmp_total_kib=unavailable
tmp_used_kib=unavailable
tmp_used_percent=unavailable'
[ "$invalid_filesystem_output" = "$expected_invalid_filesystem_output" ] || {
    printf 'invalid filesystem evidence did not fail closed:\n%s\n' \
        "$invalid_filesystem_output" >&2
    exit 1
}

link_bin=$test_root/link-bin
mkdir "$link_bin"
cat >"$link_bin/ip" <<'EOF'
#!/bin/sh
printf 'default via 192.0.2.1 dev privatewifi proto dhcp metric 600\n'
EOF
cat >"$link_bin/iw" <<'EOF'
#!/bin/sh
[ "$1:$2:$3" = 'dev:privatewifi:link' ] || exit 1
cat <<'OUTPUT'
Connected to 00:11:22:33:44:55 (on privatewifi)
	SSID: private-network-name
	freq: 5220.0
	RX: 999999 bytes (123 packets)
	TX: 888888 bytes (456 packets)
	signal: -44 dBm
	rx bitrate: 432.3 MBit/s 80MHz HE-MCS 4 HE-NSS 2
	tx bitrate: 600.4 MBit/s 80MHz HE-MCS 11 HE-NSS 1
OUTPUT
EOF
cat >"$link_bin/ping" <<'EOF'
#!/bin/sh
[ "$9" = '192.0.2.1' ] || exit 1
cat <<'OUTPUT'
PING 192.0.2.1 (192.0.2.1) 56(84) bytes of data.

--- 192.0.2.1 ping statistics ---
5 packets transmitted, 5 received, 0% packet loss, time 402ms
rtt min/avg/max/mdev = 1.149/1.227/1.420/0.097 ms
OUTPUT
EOF
chmod 0755 "$link_bin"/*
link_output=$(beryl_local_link_summary \
    "$link_bin/ip" "$link_bin/iw" "$link_bin/ping")
expected_link_output='wifi_signal_dbm=-44
wifi_frequency_mhz=5220
wifi_channel_width_mhz=80
wifi_rx_bitrate_mbps=432.3
wifi_tx_bitrate_mbps=600.4
gateway_ping_samples_sent=5
gateway_ping_samples_received=5
gateway_packet_loss_percent=0
gateway_rtt_avg_ms=1.227
gateway_rtt_mdev_ms=0.097'
[ "$link_output" = "$expected_link_output" ] || {
    printf 'Beryl local-link projection mismatch:\n%s\n' "$link_output" >&2
    exit 1
}
case "$link_output" in
    *private*|*192.0.2.1*|*00:11:22:33:44:55*)
        printf 'Beryl local-link projection leaked identity\n' >&2
        exit 1
        ;;
esac

cat >"$link_bin/ip" <<'EOF'
#!/bin/sh
printf 'default via malformed-address dev privatewifi\n'
EOF
unavailable_link_output=$(beryl_local_link_summary \
    "$link_bin/ip" "$link_bin/iw" "$link_bin/ping")
expected_unavailable_link_output='wifi_signal_dbm=unavailable
wifi_frequency_mhz=unavailable
wifi_channel_width_mhz=unavailable
wifi_rx_bitrate_mbps=unavailable
wifi_tx_bitrate_mbps=unavailable
gateway_ping_samples_sent=unavailable
gateway_ping_samples_received=unavailable
gateway_packet_loss_percent=unavailable
gateway_rtt_avg_ms=unavailable
gateway_rtt_mdev_ms=unavailable'
[ "$unavailable_link_output" = "$expected_unavailable_link_output" ] || {
    printf 'invalid Beryl local-link evidence did not fail closed:\n%s\n' \
        "$unavailable_link_output" >&2
    exit 1
}

systemd_bin=$test_root/systemd-bin
mkdir "$systemd_bin"
cat >"$systemd_bin/systemctl-clean" <<'EOF'
#!/bin/sh
printf 'no\n\nno\n\nno\n'
EOF
cat >"$systemd_bin/systemctl-stale" <<'EOF'
#!/bin/sh
printf 'no\n\nyes\n\nno\n'
EOF
cat >"$systemd_bin/systemctl-malformed" <<'EOF'
#!/bin/sh
printf 'no\n\nmaybe\n'
EOF
cat >"$systemd_bin/systemctl-empty" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$systemd_bin/systemctl-failed" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod 0755 "$systemd_bin"/*

[ "$(systemd_daemon_reload_state "$systemd_bin/systemctl-clean")" = no ] || {
    printf 'clean systemd definitions were mislabeled\n' >&2
    exit 1
}
[ "$(systemd_daemon_reload_state "$systemd_bin/systemctl-stale")" = yes ] || {
    printf 'stale systemd definitions were not detected\n' >&2
    exit 1
}
for unavailable_systemctl in \
    "$systemd_bin/systemctl-malformed" \
    "$systemd_bin/systemctl-empty" \
    "$systemd_bin/systemctl-failed"; do
    [ "$(systemd_daemon_reload_state "$unavailable_systemctl")" = \
        unavailable ] || {
        printf 'invalid systemd evidence did not fail closed: %s\n' \
            "$unavailable_systemctl" >&2
        exit 1
    }
done

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

printf 'big-red connectivity regressions: passed\n'

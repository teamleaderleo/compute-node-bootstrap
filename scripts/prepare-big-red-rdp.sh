#!/bin/sh
set -eu

mode="prepare"
keep_mac_awake_seconds=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --diagnose)
      mode="diagnose"
      ;;
    --keep-mac-awake)
      shift
      keep_mac_awake_seconds="${1:-}"
      case "$keep_mac_awake_seconds" in
        ''|*[!0-9]*)
          echo 'error=invalid_keep_awake_duration' >&2
          exit 64
          ;;
      esac
      if [ "$keep_mac_awake_seconds" -lt 60 ] || [ "$keep_mac_awake_seconds" -gt 14400 ]; then
        echo 'error=keep_awake_duration_out_of_range' >&2
        exit 64
      fi
      ;;
    *)
      echo "usage: $0 [--diagnose] [--keep-mac-awake SECONDS]" >&2
      exit 64
      ;;
  esac
  shift
done

device_name='big-red (Tailscale tunnel)'
db_path='/Users/leoli/Library/Containers/com.microsoft.rdc.macos/Data/Library/Application Support/com.microsoft.rdc.macos/com.microsoft.rdc.application-data.sqlite'

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo 'error=sqlite3_unavailable' >&2
  exit 1
fi

if ! ssh -o BatchMode=yes -o ConnectTimeout=8 big-red true >/dev/null 2>&1; then
  echo 'error=ssh_big_red_unreachable' >&2
  exit 1
fi
echo 'ssh=ready'

escaped_name=$(printf "%s" "$device_name" | sed "s/'/''/g")
saved_endpoint=$(sqlite3 "$db_path" "SELECT ZHOSTNAME FROM ZBOOKMARKENTITY WHERE ZFRIENDLYNAME='$escaped_name' LIMIT 1;")
if [ -z "$saved_endpoint" ]; then
  echo 'error=saved_windows_app_device_missing' >&2
  exit 1
fi

case "$saved_endpoint" in
  *:*)
    saved_host=${saved_endpoint%:*}
    saved_port=${saved_endpoint##*:}
    ;;
  *)
    saved_host=$saved_endpoint
    saved_port=3389
    ;;
esac

case "$saved_port" in
  ''|*[!0-9]*)
    echo 'error=saved_windows_app_endpoint_invalid' >&2
    exit 1
    ;;
esac

if ! nc -z -w 3 "$saved_host" "$saved_port" >/dev/null 2>&1; then
  echo 'error=local_rdp_tunnel_unreachable' >&2
  exit 1
fi
echo 'rdp_tunnel=ready'

if ! ssh big-red '
  systemctl --user is-active --quiet gnome-remote-desktop.service &&
  grdctl status 2>/dev/null | grep -q "Status: enabled" &&
  ss -ltn | grep -q ":3389"
' >/dev/null 2>&1; then
  echo 'error=gnome_remote_desktop_unavailable' >&2
  exit 1
fi
echo 'gnome_remote_desktop=ready'

if [ "$mode" = "diagnose" ]; then
  recent=$(ssh big-red 'journalctl --user -u gnome-remote-desktop.service --since "2 minutes ago" --no-pager 2>/dev/null' || true)
  if printf '%s\n' "$recent" | grep -q 'Session creation inhibited'; then
    echo 'diagnosis=session_creation_inhibited'
  elif printf '%s\n' "$recent" | grep -q 'client authentication failure'; then
    echo 'diagnosis=authentication_failure'
  elif printf '%s\n' "$recent" | grep -q 'TLS.*fail\|tls.*fail'; then
    echo 'diagnosis=tls_failure'
  elif printf '%s\n' "$recent" | grep -q 'ERRCONNECT_CONNECT_TRANSPORT_FAILED'; then
    echo 'diagnosis=transport_failure'
  else
    echo 'diagnosis=no_known_recent_server_error'
  fi
  exit 0
fi

screensaver_state=$(ssh big-red 'gdbus call --session --dest org.gnome.ScreenSaver --object-path /org/gnome/ScreenSaver --method org.gnome.ScreenSaver.GetActive 2>/dev/null' || true)
case "$screensaver_state" in
  *true*)
    ssh big-red 'gdbus call --session --dest org.gnome.ScreenSaver --object-path /org/gnome/ScreenSaver --method org.gnome.ScreenSaver.SetActive false >/dev/null' || true
    screensaver_state=$(ssh big-red 'gdbus call --session --dest org.gnome.ScreenSaver --object-path /org/gnome/ScreenSaver --method org.gnome.ScreenSaver.GetActive 2>/dev/null' || true)
    ;;
esac

case "$screensaver_state" in
  *false*) echo 'screensaver=inactive' ;;
  *true*)
    echo 'error=gnome_screensaver_still_active' >&2
    exit 1
    ;;
  *)
    echo 'error=gnome_screensaver_state_unknown' >&2
    exit 1
    ;;
esac

echo 'preflight=ready'

if [ -n "$keep_mac_awake_seconds" ]; then
  /usr/bin/caffeinate -u -t "$keep_mac_awake_seconds" </dev/null >/dev/null 2>&1 &
  echo "mac_user_active_assertion=ready"
  echo "mac_user_active_seconds=$keep_mac_awake_seconds"
fi

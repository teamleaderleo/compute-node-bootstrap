#!/bin/sh
set -eu

repair_credentials=0
keep_mac_awake_seconds=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repair-credentials|--setup-credentials)
      repair_credentials=1
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
      echo "usage: $0 [--setup-credentials] [--keep-mac-awake SECONDS]" >&2
      exit 64
      ;;
  esac
  shift
done

device_name='big-red (Tailscale tunnel)'
rdp_username='leo'
windows_app_bin='/Users/leoli/Applications/Windows App.app/Contents/MacOS/Windows App'
db_path='/Users/leoli/Library/Containers/com.microsoft.rdc.macos/Data/Library/Application Support/com.microsoft.rdc.macos/com.microsoft.rdc.application-data.sqlite'
prepare_script=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/prepare-big-red-rdp.sh

if [ ! -x "$prepare_script" ]; then
  echo 'error=rdp_prepare_script_missing' >&2
  exit 1
fi
if [ ! -x "$windows_app_bin" ]; then
  echo 'error=windows_app_missing' >&2
  exit 1
fi
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo 'error=sqlite3_unavailable' >&2
  exit 1
fi

if ! ssh big-red '
  set -eu
  "$HOME/.local/bin/seed-big-red-rdp-session-credentials" >/dev/null
  gsettings set org.gnome.desktop.remote-desktop.rdp enable true
  systemctl --user disable --now gnome-remote-desktop-headless.service >/dev/null 2>&1 || true
  systemctl --user enable --now gnome-remote-desktop.service >/dev/null
'; then
  echo 'error=gnome_rdp_session_credential_setup_failed' >&2
  exit 1
fi

if [ -n "$keep_mac_awake_seconds" ]; then
  "$prepare_script" --keep-mac-awake "$keep_mac_awake_seconds"
else
  "$prepare_script"
fi

escaped_name=$(printf '%s' "$device_name" | sed "s/'/''/g")
bookmark_row=$(sqlite3 -separator '|' "$db_path" "SELECT ZHOSTNAME,ZID FROM ZBOOKMARKENTITY WHERE ZFRIENDLYNAME='$escaped_name' LIMIT 1;")
if [ -z "$bookmark_row" ]; then
  echo 'error=saved_windows_app_device_missing' >&2
  exit 1
fi
saved_endpoint=${bookmark_row%%|*}
bookmark_id=${bookmark_row#*|}

if [ -z "$saved_endpoint" ] || [ -z "$bookmark_id" ]; then
  echo 'error=saved_windows_app_device_invalid' >&2
  exit 1
fi

rdp_status=$(ssh big-red 'grdctl status 2>/dev/null' || true)
credentials_missing=0
if printf '%s\n' "$rdp_status" | grep -q 'Username: (empty)'; then
  credentials_missing=1
fi
if printf '%s\n' "$rdp_status" | grep -q 'Password: (empty)'; then
  credentials_missing=1
fi

if [ "$credentials_missing" -eq 1 ] && [ "$repair_credentials" -ne 1 ]; then
  echo 'error=gnome_rdp_credentials_missing' >&2
  echo "recovery=$0 --setup-credentials" >&2
  exit 1
fi

if [ "$repair_credentials" -eq 1 ]; then
  rdp_secret=$(/usr/bin/openssl rand -hex 24)
  if ! ssh big-red /usr/bin/timeout 15s grdctl --headless rdp set-credentials \
      "$rdp_username" "$rdp_secret" >/dev/null; then
    unset rdp_secret
    echo 'error=gnome_rdp_credential_update_failed' >&2
    exit 1
  fi
  if ! "$windows_app_bin" --script bookmark write "$bookmark_id" \
      --username "$rdp_username" --password "$rdp_secret" >/dev/null; then
    unset rdp_secret
    echo 'error=windows_app_credential_update_failed' >&2
    exit 1
  fi
  unset rdp_secret
  if ! ssh big-red '
    "$HOME/.local/bin/seed-big-red-rdp-session-credentials" >/dev/null &&
    systemctl --user restart gnome-remote-desktop.service
  '; then
    echo 'error=gnome_rdp_restart_failed' >&2
    exit 1
  fi
  echo 'rdp_credentials=repaired'
fi

rdp_status=$(ssh big-red 'grdctl status 2>/dev/null' || true)
if printf '%s\n' "$rdp_status" | grep -q 'Username: (empty)\|Password: (empty)'; then
  echo 'error=gnome_rdp_credentials_missing_after_repair' >&2
  exit 1
fi
echo 'rdp_credentials=ready'

launch_epoch=$(date +%s)
if ssh big-red "ss -Htn state established '( sport = :3389 )' | grep -q ." >/dev/null 2>&1; then
  echo 'rdp_session=ready'
  exit 0
fi

# A stale authentication sheet can cover the saved-device view. Terminating only
# this client process resets that UI state before invoking the named saved device.
/usr/bin/pkill -TERM -x 'Windows App' >/dev/null 2>&1 || true
attempt=0
while /usr/bin/pgrep -x 'Windows App' >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 5 ]; then
    echo 'error=windows_app_would_not_quit' >&2
    exit 1
  fi
  sleep 1
done

/usr/bin/open -a '/Users/leoli/Applications/Windows App.app'
if ! /usr/bin/osascript - "$device_name" <<'APPLESCRIPT'
on run argv
  set deviceName to item 1 of argv
  tell application "Windows App" to activate
  tell application "System Events"
    tell process "Windows App"
      repeat 20 times
        try
          set card to group 1 of group 2 of list 1 of list 1 of scroll area 1 of group 1 of splitter group 1 of window 1
          if (description of card as text) is deviceName then
            perform action "AXPress" of card
            return
          end if
        end try
        delay 0.5
      end repeat
      error "saved Windows App device not found"
    end tell
  end tell
end run
APPLESCRIPT
then
  echo 'error=windows_app_saved_device_launch_failed' >&2
  exit 1
fi
echo 'rdp_launch=requested'

attempt=0
while [ "$attempt" -lt 20 ]; do
  attempt=$((attempt + 1))
  if ssh big-red "ss -Htn state established '( sport = :3389 )' | grep -q ." >/dev/null 2>&1; then
    sleep 2
    if ssh big-red "ss -Htn state established '( sport = :3389 )' | grep -q ." >/dev/null 2>&1; then
      echo 'rdp_session=ready'
      exit 0
    fi
  fi
  sleep 1
done

recent=$(ssh big-red "journalctl --user -u gnome-remote-desktop.service --since '@$launch_epoch' --no-pager 2>/dev/null" || true)
if printf '%s\n' "$recent" | grep -q 'Credentials are not set'; then
  diagnosis='credentials_missing'
elif printf '%s\n' "$recent" | grep -q 'Session creation inhibited'; then
  diagnosis='session_creation_inhibited'
elif printf '%s\n' "$recent" | grep -q 'client authentication failure'; then
  diagnosis='authentication_failure'
elif printf '%s\n' "$recent" | grep -qi 'tls.*fail'; then
  diagnosis='tls_failure'
else
  diagnosis='connection_not_established'
fi

echo "error=rdp_session_failed" >&2
echo "diagnosis=$diagnosis" >&2
exit 1

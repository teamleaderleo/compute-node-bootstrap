#!/bin/sh
set -eu

credentials_file="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-remote-desktop/credentials.ini"
if [ ! -r "$credentials_file" ]; then
  echo 'error=persistent_rdp_credential_missing' >&2
  exit 1
fi

serialized=$(sed -n 's/^credentials=//p' "$credentials_file")
if [ -z "$serialized" ]; then
  echo 'error=persistent_rdp_credential_empty' >&2
  exit 1
fi

attempt=0
while [ "$attempt" -lt 30 ]; do
  attempt=$((attempt + 1))
  if busctl --user get-property \
      org.freedesktop.secrets \
      /org/freedesktop/secrets/collection/session \
      org.freedesktop.Secret.Collection Locked 2>/dev/null | grep -q 'false'; then
    break
  fi
  sleep 1
done

if ! busctl --user get-property \
    org.freedesktop.secrets \
    /org/freedesktop/secrets/collection/session \
    org.freedesktop.Secret.Collection Locked 2>/dev/null | grep -q 'false'; then
  unset serialized
  echo 'error=session_keyring_unavailable' >&2
  exit 1
fi

printf '%s' "$serialized" | secret-tool store \
  --collection=session \
  --label='GNOME Remote Desktop RDP credentials' \
  xdg:schema org.gnome.RemoteDesktop.RdpCredentials
unset serialized
echo 'rdp_session_credential=ready'

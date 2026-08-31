#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  printf 'Run this script with sudo.\n' >&2
  exit 1
fi

operator_user=${SUDO_USER:-leo}
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

printf '== Finish Ubuntu package updates ==\n'
apt update
DEBIAN_FRONTEND=noninteractive apt full-upgrade -y
apt install -y \
  unattended-upgrades \
  curl \
  ca-certificates \
  ethtool \
  networkd-dispatcher \
  intel-media-va-driver-non-free \
  vainfo

systemctl enable --now apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service

printf '\n== Keep the open node awake and make lid-close safe ==\n'
install -d -m 0755 /etc/systemd/logind.conf.d
install -o root -g root -m 0644 "${script_dir}/../logind.conf.d/60-unattended-node.conf" /etc/systemd/logind.conf.d/60-unattended-node.conf
systemctl unmask sleep.target suspend.target
systemctl mask hibernate.target hybrid-sleep.target

printf '\n== Allow the operator account to administer the unattended node ==\n'
cat >/etc/sudoers.d/60-big-red-admin <<EOF
${operator_user} ALL=(ALL:ALL) NOPASSWD: ALL
EOF
chmod 0440 /etc/sudoers.d/60-big-red-admin
visudo -cf /etc/sudoers.d/60-big-red-admin

printf '\n== Keep Wi-Fi responsive while the machine is unattended ==\n'
install -d -m 0755 /etc/NetworkManager/conf.d
cat >/etc/NetworkManager/conf.d/60-big-red-reliable-wifi.conf <<'EOF'
[connection]
wifi.powersave=2
EOF

wifi_interface=$(find /sys/class/net -mindepth 1 -maxdepth 1 -type l -printf '%f\n' | while read -r interface; do
  if [[ $(cat "/sys/class/net/${interface}/type") == 1 && -d "/sys/class/net/${interface}/wireless" ]]; then
    printf '%s\n' "${interface}"
    break
  fi
done)

if [[ -n ${wifi_interface} ]]; then
  wifi_connection=$(nmcli -g GENERAL.CONNECTION device show "${wifi_interface}" | head -n 1)
  if [[ -n ${wifi_connection} && ${wifi_connection} != -- ]]; then
    nmcli connection modify "${wifi_connection}" 802-11-wireless.powersave 2
    nmcli device reapply "${wifi_interface}" || true
  fi

  install -d -m 0755 /etc/networkd-dispatcher/routable.d
  cat >/etc/networkd-dispatcher/routable.d/50-tailscale <<EOF
#!/usr/bin/env bash
/usr/sbin/ethtool -K ${wifi_interface} rx-udp-gro-forwarding on rx-gro-list off
EOF
  chmod 0755 /etc/networkd-dispatcher/routable.d/50-tailscale
  /etc/networkd-dispatcher/routable.d/50-tailscale || true

  cat >/etc/systemd/system/tailscale-udp-gro.service <<EOF
[Unit]
Description=Apply Tailscale UDP GRO forwarding optimization
Wants=network-online.target
After=network-online.target NetworkManager-wait-online.service

[Service]
Type=oneshot
ExecStart=/usr/sbin/ethtool -K ${wifi_interface} rx-udp-gro-forwarding on rx-gro-list off
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now tailscale-udp-gro.service
fi

printf '\n== Make the GNOME desktop predictable after every login ==\n'
install -o root -g root -m 0755 "${script_dir}/big-red-session-settings" /usr/local/sbin/big-red-session-settings

install -d -m 0755 -o "${operator_user}" -g "${operator_user}" "/home/${operator_user}/.config/autostart"
cat >"/home/${operator_user}/.config/autostart/big-red-session-settings.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=big-red unattended desktop settings
Exec=/usr/local/sbin/big-red-session-settings
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
chown "${operator_user}:${operator_user}" "/home/${operator_user}/.config/autostart/big-red-session-settings.desktop"

# The browser profile already owns authentication and is configured to restore
# its last session. Autostart only opens that existing profile after the
# attended auto-login; it does not create or copy credentials.
install -o "${operator_user}" -g "${operator_user}" -m 0644 \
  "${script_dir}/../machines/redmibook-pro-16-2025/microsoft-edge-session.desktop" \
  "/home/${operator_user}/.config/autostart/microsoft-edge-session.desktop"

install -d -m 0755 -o "${operator_user}" -g "${operator_user}" "/home/${operator_user}/.config/systemd/user"
install -o "${operator_user}" -g "${operator_user}" -m 0644 \
  "${script_dir}/../systemd/chatgpt-remote-host.service" \
  "/home/${operator_user}/.config/systemd/user/chatgpt-remote-host.service"
if [[ -S /run/user/1000/bus ]]; then
  sudo -u "${operator_user}" env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
    systemctl --user daemon-reload
  sudo -u "${operator_user}" env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
    systemctl --user enable chatgpt-remote-host.service
  sudo -u "${operator_user}" env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus /usr/local/sbin/big-red-session-settings
fi

printf '\n== Install the bounded big-red diagnostic ==\n'
install -o root -g root -m 0755 "${script_dir}/big-red-connectivity-check" /usr/local/bin/big-red-connectivity-check
# An early manual installation used sbin, which precedes bin in the operator's
# PATH. Keep that exact legacy pathname as an alias so it cannot shadow a newer
# canonical install with stale bytes.
ln -sfnT ../bin/big-red-connectivity-check /usr/local/sbin/big-red-connectivity-check

printf '\n== Enable Linux forwarding for the future Tailscale exit node ==\n'
cat >/etc/sysctl.d/99-tailscale.conf <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl -p /etc/sysctl.d/99-tailscale.conf

printf '\n== Install Tailscale ==\n'
if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
systemctl enable --now tailscaled
tailscale set --operator="${operator_user}"
systemctl enable ssh NetworkManager networkd-dispatcher

printf '\nUnattended-node configuration complete.\n'
printf 'Reboot once to activate the final package and Wi-Fi changes.\n'

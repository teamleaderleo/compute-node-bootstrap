#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  printf 'Run this script with sudo.\n' >&2
  exit 1
fi

operator_user=${SUDO_USER:-leo}

printf '== Finish Ubuntu package updates ==\n'
apt update
DEBIAN_FRONTEND=noninteractive apt full-upgrade -y
apt install -y unattended-upgrades curl ca-certificates ethtool networkd-dispatcher

systemctl enable --now apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service

printf '\n== Keep the node awake and reachable ==\n'
install -d -m 0755 /etc/systemd/logind.conf.d
cat >/etc/systemd/logind.conf.d/60-unattended-node.conf <<'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
IdleAction=ignore
EOF
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

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
cat >/usr/local/sbin/big-red-session-settings <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Keep the remote host awake while allowing the high-resolution panel to sleep.
gsettings set org.gnome.settings-daemon.plugins.power ambient-enabled false
gsettings set org.gnome.settings-daemon.plugins.power idle-dim true
gsettings set org.gnome.settings-daemon.plugins.power idle-brightness 30
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 0
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
gsettings set org.gnome.desktop.session idle-delay 'uint32 600'
gsettings set org.gnome.desktop.screensaver lock-enabled false
gsettings set org.gnome.desktop.screensaver lock-delay 'uint32 0'
EOF
chmod 0755 /usr/local/sbin/big-red-session-settings

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
if [[ -S /run/user/1000/bus ]]; then
  sudo -u "${operator_user}" env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus /usr/local/sbin/big-red-session-settings
fi

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
printf 'Reboot once to activate the final package, Wi-Fi and sleep-policy changes.\n'

# `big-red` bootstrap and remote takeover

The in-person handoff is complete. Ubuntu was installed by the owner and Codex took over after the first OpenSSH login.

## Finished on 2026-08-28

- [x] Erased the factory Windows installation and installed Ubuntu 26.04 LTS.
- [x] Created Ubuntu user `leo` and hostname `big-red`.
- [x] Recorded the actual hardware, firmware, storage, battery and network state.
- [x] Installed OpenSSH, development tools, automatic updates and the repository baseline packages.
- [x] Set `Asia/Shanghai`, enabled NTP and enabled automatic login.
- [x] Installed a dedicated conventional SSH key and verified both LAN and Tailscale logins.
- [x] Joined `big-red` to the existing tailnet and disabled key expiry.
- [x] Disabled Tailscale SSH after conventional OpenSSH was proven; this avoids recurring tailnet web checks.
- [x] Enabled IP forwarding, advertised an exit node and approved it in the Tailscale admin console.
- [x] Disabled GNOME idle dimming, ambient brightness and automatic suspend.
- [x] Masked Linux sleep, suspend and hibernate targets and made lid close a no-op.
- [x] Disabled Wi-Fi power saving and installed Tailscale's recommended UDP GRO forwarding hook.
- [x] Enabled passwordless `sudo` for `leo` so future remote maintenance needs no physical approval.
- [x] Installed Codex CLI and the preview Linux ChatGPT/Codex desktop app from OpenAI's official packages.
- [x] Rebooted twice and verified that networking, Tailscale, OpenSSH, auto-login, no-sleep policy and the short remote alias return automatically.

The actual state and recovery commands are in [`BIG_RED_STATE.md`](BIG_RED_STATE.md).

## Still deliberately postponed

- [ ] Move `big-red` to its long-term residential Wi-Fi and confirm Tailscale reconnects.
- [ ] On the Beryl 7, select `big-red` as Custom Exit Node only after testing the exit path with a non-work device.
- [ ] Verify DNS and public egress through that path.
- [ ] Disable Custom Exit Node and confirm the existing OpenClash/Bandwagon path returns immediately.
- [ ] Decide whether a GitHub Actions runner or other workload service is required.

No battery-charge threshold was set because Ubuntu exposes no supported charge-limit control for the installed battery/firmware combination. Keep the OEM charger attached for unattended use.

## If the machine becomes unreachable

Normal operation should not require anyone locally: it does not sleep, Tailscale and SSH start at boot, and `leo` can administer it remotely. If power was lost long enough for the battery to empty or the machine was shut down, someone must press the physical Power button. No reliable remote power-on mechanism was exposed by the current Wi-Fi or firmware.

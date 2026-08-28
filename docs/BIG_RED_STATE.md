# `big-red` observed state and recovery

Observed on 2026-08-28 after the Ubuntu installation. This file intentionally contains no credentials or Tailscale enrollment material.

## Machine

- XIAOMI REDMI Book Pro 16 2025, SKU TM2409-63077
- firmware RMAAR6B0P0606, dated 2025-05-09
- Intel Core Ultra 7 255H
- 32 GB installed memory (about 30 GiB visible to Linux)
- YMTC PC411-1TB-D 953.9 GiB NVMe
- Intel Arrow Lake graphics using `i915`
- Intel CNVi Wi-Fi using `iwlwifi`
- SUNWODA BX90 battery, roughly 96 Wh design capacity
- Ubuntu 26.04 LTS, hostname `big-red`, user `leo`, timezone `Asia/Shanghai`

The OEM 140 W USB-C charger is recognized correctly. Linux exposes no battery charge-threshold control on this firmware, so no charge ceiling was configured.

## Operator access

From the configured Mac, the primary command is:

```bash
ssh big-red
```

This uses conventional OpenSSH key authentication over `tailscale nc`. The ProxyCommand matters because Stash installs a competing `100.64.0.0/10` route on macOS; ordinary system routing to a Tailscale address can otherwise go to Stash even while `tailscale ping` works.

The Mac entry is:

```sshconfig
Host big-red
    HostName big-red
    User leo
    IdentityFile ~/.ssh/id_ed25519_big_red
    IdentitiesOnly yes
    ProxyCommand /usr/local/bin/tailscale nc %h %p
```

While the Mac is on the same Big Brouter LAN, `ssh big-red-lan` is a secondary shortcut. Its current DHCP address may change, so it is not the durable remote path.

Tailscale SSH itself is off. Tailscale supplies private reachability; the normal OpenSSH service supplies authentication. This avoids the recurring browser approval that the tailnet's SSH check policy caused.

## Unattended behavior

- `ssh`, `tailscaled`, NetworkManager, `networkd-dispatcher` and unattended upgrades start at boot.
- Tailscale key expiry is disabled for `big-red`.
- GNOME automatic suspend, ambient brightness and idle dimming are disabled.
- systemd sleep, suspend, hibernate and hybrid-sleep targets are masked.
- Closing the lid does nothing, including on battery.
- Wi-Fi power saving is disabled.
- The Wi-Fi UDP GRO forwarding optimization is restored whenever the interface becomes routable.
- `leo` has passwordless `sudo` for unattended maintenance.
- Linux IPv4/IPv6 forwarding is enabled.
- `big-red` advertises a Tailscale exit node and the route is approved.
- Codex CLI 0.150.1 and the official preview Linux ChatGPT/Codex desktop app 26.825.31414 are installed.

## Quick checks

```bash
ssh big-red
sudo systemctl --no-pager --full status ssh tailscaled
tailscale status
tailscale netcheck
systemctl is-enabled sleep.target suspend.target hibernate.target hybrid-sleep.target
```

The four sleep targets should report `masked`.

## Router status and later migration

The Beryl 7 remains enrolled in Tailscale but has no Custom Exit Node selected. Its existing OpenClash/Bandwagon configuration was not replaced or removed. During the final reboot test, `big-red` successfully rejoined **Ministry of Routing MLO** and received `192.168.8.107`; internet and Tailscale connectivity both returned automatically.

When `big-red` reaches its long-term residential connection:

1. confirm `ssh big-red` works from another network;
2. test `big-red` as an exit node directly from a non-work device;
3. record the Beryl's current OpenClash selection and public egress;
4. select `big-red` as the Beryl Custom Exit Node;
5. test internet, DNS and the intended work applications;
6. disable Custom Exit Node once and verify the original OpenClash/Bandwagon route returns.

The machine cannot be reached while it is genuinely powered off. The practical design is therefore to keep it on the OEM charger and prevent sleep. After a shutdown or complete battery drain, the physical fallback is one press of the Power button; services and remote access then start automatically.


## Connectivity hardening — 2026-08-28

A later reliability audit found that the Beryl's OpenClash Fake-IP DNS was
occasionally giving Tailscale synthetic `198.18.0.0/15` destinations that the
Tailscale daemon could not use. The router now excludes Tailscale domains from
Fake-IP responses while retaining the existing OpenClash profile and egress.

The host also has server-side SSH keepalives, an enabled graphical-session
service that starts/restarts the ChatGPT desktop app, and a credential-free
`big-red-connectivity-check` diagnostic command.

See [Connectivity and Codex Remote runbook](CONNECTIVITY_AND_CODEX_REMOTE.md)
for the exact change, verification evidence, Mac/phone notes, and rollback.

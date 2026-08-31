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

The OEM 140 W USB-C charger is recognized correctly. Linux's standard power-supply interface exposes no battery threshold, but a later read-only audit verified the model-specific Xiaomi MIFS charge-care method in this machine's own ACPI tables. See [the guarded 80% runbook](BIG_RED_CHARGE_LIMIT.md).

As of 2026-08-29, the charge cap remains inactive and the battery reports 100%. Ubuntu's `acpi-call-dkms` package built a module for kernel `7.0.0-30-generic` and signed it with the machine-local DKMS key, but Secure Boot correctly rejected it because that key has not yet been physically enrolled. The model-locked helper is installed at `/usr/local/sbin/big-red-charge-limit`; no charge command, boot service, module-load declaration, or udev re-arm rule has been applied. A briefly staged MOK request was revoked before reboot so ordinary family restarts remain uneventful; there is currently no pending MOK action. Re-stage it only immediately before the attended enrollment and reversible test. Do not disable Secure Boot to bypass this gate.

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

Outbound GitHub access uses a separate, purpose-specific Ed25519 identity:

```text
~/.ssh/id_ed25519_github_big_red_codex
SHA256:1MtOsAKGhX9YPp1pLfwIAIgRfktQT5havzVmJsHaQSc
```

GitHub registered the corresponding public key as `big-red Codex GitHub
2026-08-29`. `~/.ssh/config` binds it only to `github.com` with
`IdentitiesOnly yes`; GitHub CLI and the canonical Leo-owned clones under
`/home/leo/Projects` use SSH transport. This is intentionally distinct from
the Mac-side `~/.ssh/id_ed25519_big_red` identity used to enter this host. Do
not copy either private key between machines or replace one with the other.

## Unattended behavior

- `ssh`, `tailscaled`, NetworkManager, `networkd-dispatcher` and unattended upgrades start at boot.
- Tailscale key expiry is disabled for `big-red`.
- GNOME automatic idle suspend and ambient brightness are disabled. Idle dimming is enabled, and the display blanks after 10 minutes of inactivity without locking or suspending the open host. The internal panel currently uses its native 3072x1920 mode at 165 Hz and 150% scale.
- systemd sleep and suspend are available; hibernate and hybrid-sleep remain masked.
- Closing the lid requests suspend on AC, battery, and while docked. This intuitive transport safety takes precedence over remote availability after somebody deliberately closes the machine.
- Wi-Fi power saving is disabled.
- The Wi-Fi UDP GRO forwarding optimization is restored whenever the interface becomes routable.
- `leo` has passwordless `sudo` for unattended maintenance.
- Linux IPv4/IPv6 forwarding is enabled.
- `big-red` advertises a Tailscale exit node and the route is approved.
- Codex CLI 0.150.1 and the official preview Linux ChatGPT/Codex desktop app 26.825.31414 are installed.
- ChatGPT and the existing Edge profile start after automatic graphical login; Edge restores its
  last session. Authentication remains in each application's existing local profile.
- Intel's non-free `iHD` VA-API media driver is installed. H.264 encode support was verified with `vainfo`, allowing GNOME Remote Desktop to use the GPU instead of software encoding.
- The Ubuntu-native workstation set provides LibreOffice Writer/Calc/Impress, Showtime, Amberol,
  File Roller and Remmina plus system `ripgrep`, `sqlite3` and `hyperfine`. Office documents no
  longer resolve to ChatGPT; PDF/image defaults are Papers/Loupe. See
  [`BIG_RED_WORKSTATION.md`](BIG_RED_WORKSTATION.md) for the reproducible apply, verification and
  rollback boundary.
- GNOME LocalSearch indexes the standard Desktop/Documents/Downloads/media folders, not all of `$HOME`. Repositories, build trees, and language caches use project-aware search (`rg`, editors) instead of desktop metadata extraction.

## Graphical and phone access

GNOME Remote Desktop is enabled for interactive control on TCP 3389. It is not publicly forwarded. Air Blue reaches it through a persistent local SSH tunnel:

```text
Windows App -> 127.0.0.1:13389 -> ssh big-red -> 127.0.0.1:3389
```

The tunnel is maintained by Air Blue's `com.teamleaderleo.big-red-rdp-tunnel` LaunchAgent. The saved Windows App device is **big-red (Tailscale tunnel)**. Its credential stays in Windows App on Air Blue and is not recorded in this repository.

The path was verified from Air Blue on a phone hotspot while `big-red` remained on the Beryl LAN. Live video and mouse input worked. A fresh session after the media-driver installation logged successful VA-API initialization and accepted H.264 AVC444/AVC420 capabilities.

Codex Remote can control Codex tasks running on `big-red`; it is separate from whole-desktop RDP. Pair it through Codex Desktop rather than treating it as a graphical recovery path.

## Quick checks

```bash
ssh big-red
sudo systemctl --no-pager --full status ssh tailscaled
tailscale status
tailscale netcheck
systemctl is-enabled sleep.target suspend.target hibernate.target hybrid-sleep.target
vainfo --display drm --device /dev/dri/renderD128
XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user status gnome-remote-desktop.service
```

The expected results are `static`, `static`, `masked`, `masked`: suspend is available, while hibernate and hybrid sleep remain disabled.

Rollback to the former always-awake node policy is explicit but no longer recommended for family use: change the three `HandleLidSwitch*` values in `/etc/systemd/logind.conf.d/60-unattended-node.conf` to `ignore`, mask `sleep.target` and `suspend.target`, then run `sudo systemctl reload systemd-logind`. Reapply the tracked configuration and unmask those two targets to restore the current family-safe policy.

GNOME LocalSearch previously indexed all of `$HOME`, reached Go module caches, misclassified `*.mod` files as audio, and later segfaulted once. The service restarted successfully, but that work has no value for Quarry/Glaeda development. After narrowing the scope, its supported `reset --filesystem` operation rebuilt an idle index containing only 12 files and 20 folders; no source file was touched. Restore the distribution-wide-home search scope, if ever wanted, with:

```bash
gsettings reset org.freedesktop.Tracker3.Miner.Files index-recursive-directories
```

## Router status and later migration

The Beryl 7 remains enrolled in Tailscale but has no Custom Exit Node selected. Its existing OpenClash/Bandwagon configuration was not replaced or removed. During the final reboot test, `big-red` successfully rejoined **Ministry of Routing MLO** and received `192.168.8.107`; internet and Tailscale connectivity both returned automatically.

When `big-red` reaches its long-term residential connection:

1. confirm `ssh big-red` works from another network;
2. test `big-red` as an exit node directly from a non-work device;
3. record the Beryl's current OpenClash selection and public egress;
4. select `big-red` as the Beryl Custom Exit Node;
5. test internet, DNS and the intended work applications;
6. disable Custom Exit Node once and verify the original OpenClash/Bandwagon route returns.

The machine cannot be reached while suspended or genuinely powered off. For unattended remote operation, leave it open on a hard surface and connected to the OEM charger; the panel can still blank. After lid-open/resume, shutdown, or complete battery drain, services and remote access are expected to return automatically, but the physical fallback is one press of the Power button.


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

## Display power update — 2026-08-29

The internal display runs its native 3072x1920 mode at 165 Hz and 150% scale, starts each login at raw backlight 150/496 (about 30%), dims when idle, and blanks after 10 minutes. Local brightness keys can raise or lower it after login. Local input wakes the display immediately. Blanking does not stop ChatGPT, SSH, Tailscale, builds, or other background work; automatic suspend and screen locking remain disabled. A live desktop capture remained fully readable while the physical backlight reported blank, confirming that desktop-control routes can still inspect the session.

A native 120 Hz test applied successfully and survived an immediate blank/wake cycle, but the shared graphical session later reasserted 165 Hz twice while other roots and GNOME Remote Desktop were active. Retry only in a quiet, locally observed window, then verify after blank/wake, Remote Desktop connection, relogin, and reboot before making it policy:

```bash
gdctl set --persistent --layout-mode logical \
  --logical-monitor --primary --scale 1.5 \
  --monitor eDP-1 --mode '3072x1920@120.001'
```

Restore the previous never-blank behavior with:

```bash
gsettings set org.gnome.settings-daemon.plugins.power idle-dim false
gsettings set org.gnome.desktop.session idle-delay 'uint32 0'
```

For transport, closing the lid requests suspend. Wait a few seconds before putting it in a bag; use Power Off instead for long transport or storage. For unattended remote work, keep the lid open on a hard surface. For ordinary desk use or movies, leave the Balanced profile selected; full-screen media should inhibit idle blanking through GNOME's standard mechanism.

The round fingerprint reader at the keyboard's upper right is also the physical power button. GNOME currently displays its behavior as **Power Off** and handles the button interactively. Prefer a short press or GNOME's system-menu Power Off action for an orderly shutdown; holding the button is an emergency hard-off and can lose active work. A suspended Wi-Fi/Tailscale host cannot currently be relied upon to receive or act on a remote wake request, so remote operation requires leaving the lid open.

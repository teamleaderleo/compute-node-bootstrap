# Connectivity and Codex Remote runbook

Last verified on `big-red`: 2026-08-30 (Asia/Shanghai).

This file contains no credentials, enrollment URLs, or private keys.

## Separate the two remote paths

There are two independent paths:

1. **ChatGPT/Codex Remote from iOS or Android** uses ChatGPT's secure relay. It
   does not require Tailscale on the phone. The desktop app must remain running,
   awake, online, signed in to the same account/workspace, and have Remote
   Control enabled.
2. **Codex projects on an SSH host** use OpenSSH to start the remote Codex app
   server. The operator Mac reaches `big-red` through `tailscale nc`; see
   [REMOTE_ACCESS.md](REMOTE_ACCESS.md).

The official Remote documentation currently describes macOS and Windows hosts.
Remote pairing was nevertheless observed to work in the preview Linux desktop
app installed on `big-red`. Treat that Linux path as preview behavior and
re-pair after app updates if the host disappears.

Official reference:
https://learn.chatgpt.com/docs/remote-connections

## Host availability configuration

- GNOME automatic idle suspend remains disabled while the lid is open. Closing the lid explicitly requests suspend; hibernate and hybrid sleep remain disabled.
- GNOME dims the panel and blanks it after 10 idle minutes without locking or
  suspending the host.
- Automatic login is enabled for `leo`.
- Wi-Fi power saving is disabled on `MinistryOfRouting-MLO`.
- `ssh`, `tailscaled`, NetworkManager, resolved, and Avahi start at boot.
- `~/.config/systemd/user/chatgpt-remote-host.service` is enabled for the
  graphical session. It starts ChatGPT ten seconds after login and restarts it
  after a process failure.
- `/etc/ssh/sshd_config.d/60-big-red-remote-reliability.conf` sends a
  server-side keepalive every 45 seconds and tolerates four missed replies.
- `/usr/local/bin/big-red-connectivity-check`, sourced from
  `scripts/big-red-connectivity-check`, prints a bounded, credential-free
  health snapshot. It summarizes services, sleep targets, effective GNOME
  screen/idle behavior, effective logind lid actions, Tailscale reachability,
  DNS Fake-IP classification, Chrony, capacity/thermal/power state, Bluetooth noise, and the
  ChatGPT launcher, desktop, Codex remote-control process, and private local
  control-listener state without printing process arguments, socket paths, or
  full network addresses. When
  the purpose-specific `ssh beryl7` key is available on the Beryl LAN, it also
  prints router service/process counts, RSS, available memory, current-boot OOM
  count, and SoC temperature. That optional probe is key-only and capped at
  seven seconds; it reports `router_ssh=unavailable` instead of prompting when
  the router or identity is unavailable.

The host-health section reads CPU-package temperature/critical thresholds from
hwmon. When the root filesystem is directly backed by an NVMe namespace, it
binds that controller to its own hwmon child for temperature/critical thresholds
and makes one five-second, noninteractive, read-only SMART-log request. It
prints only health counters: critical warnings, spare, wear,
media/error-log counts, unsafe shutdowns, and time above warning/critical
temperature. It never prints the drive model, serial number, firmware, device
path, namespace size, or raw SMART payload. `nvme_smart=unavailable` means the
bounded read was unavailable or failed validation; it is not itself a drive
failure.

The ChatGPT user service was enabled without restarting the running desktop app.
It takes ownership on the next graphical login or reboot. During the current
pre-existing session, the diagnostic therefore reports an enabled but inactive
user service, an active graphical session, and an active desktop process. That
combination is expected until the coordinated login/reboot validation; do not
start a second instance merely to make the service state say active.

The launcher unit and the actual local Remote transport are separate evidence.
On 2026-08-30 the launcher remained inactive for the reason above, while one
user-owned `codex app-server --remote-control --listen unix://` process and its
private local control socket were both live. The diagnostic reports those as
`remote_control_processes=1`, `local_control_socket=listening_owned`, and
`local_remote_control_transport=ready`. That proves the local process/listener
shape only; it does not claim that a phone is paired or that the external relay
is reachable. Keep the coordinated next-login service validation in the
backlog, but do not treat an inactive launcher alone as a Remote outage.

## Root cause found on 2026-08-28

The active Beryl 7 OpenClash profile uses Fake-IP DNS. Tailscale processes are
not always captured by OpenClash's transparent-proxy path, so Tailscale was
sometimes handed a synthetic `198.18.0.0/15` destination without a matching
proxy interception.

The journal showed:

- relay disconnects and `no-derp-connection` health warnings;
- control-plane map timeouts;
- `controlplane.tailscale.com` resolving to `198.18.x.x`;
- failed connections to those synthetic addresses.

This explained intermittent Tailscale/SSH behavior even though the Intel Wi-Fi
link and OpenSSH service were healthy.

## Beryl change

In **OpenClash → Overwrite Settings → DNS Settings**:

- enabled **Fake-IP-Filter** in **Blacklist Mode**;
- kept the existing list;
- appended:

```text
tailscale.com
*.tailscale.com
tailscale.io
*.tailscale.io
ts.net
*.ts.net
connectivity-check.ubuntu.com
ntp.ubuntu.com
*.ntp.ubuntu.com
ntp-bootstrap.ubuntu.com
```

`connectivity-check.ubuntu.com` is included because Tailscale's captive-portal
check was also receiving an unusable Fake-IP answer. The three Ubuntu NTP
patterns were added on 2026-08-29 after all four `*.ntp.ubuntu.com` pools and
`ntp-bootstrap.ubuntu.com` were observed in `198.18.0.0/15`; Chrony's NTS-KE
traffic cannot rely on OpenClash intercepting those synthetic destinations.
The override was committed and applied. The selected
`beryl7-openclash-cn-direct-v2.yaml` profile, proxy mode, and proxy credentials
were not changed.

Immediately after applying:

- `controlplane.tailscale.com` returned a real `192.200.x.x` address;
- `connectivity-check.ubuntu.com` returned a real `91.189.91.x` address;
- `tailscaled` completed a fresh authenticated control-plane login;
- the local Beryl peer was direct at roughly 2–3 ms;
- OpenClash continued providing the existing Los Angeles internet egress.

After the NTP addition on 2026-08-29:

- `1` through `4.ntp.ubuntu.com` and `ntp-bootstrap.ubuntu.com` all returned
  real Ubuntu addresses rather than `198.18.0.0/15`;
- a Chrony-only restart forced immediate re-resolution, selected a real
  `185.125.190.x` source, and retained valid NTS authentication cookies;
- Chrony reported `Leap status: Normal` with no restart warnings;
- the Beryl Tailscale path remained direct and the full
  `big-red-connectivity-check` passed.

The DERP region can still be in North America because OpenClash provides U.S.
egress. That is expected; the important correction is that Tailscale control
domains are no longer unusable Fake-IP destinations.

## Quick check

Run:

```bash
big-red-connectivity-check
```

Focused checks:

```bash
dig +short @192.168.8.1 controlplane.tailscale.com A
dig +short @192.168.8.1 1.ntp.ubuntu.com A
dig +short @192.168.8.1 ntp-bootstrap.ubuntu.com A
chronyc -n tracking
sudo chronyc -N authdata
tailscale status
tailscale ping -c 3 gl-mt3600be
tailscale netcheck
journalctl -u tailscaled --since "30 minutes ago" --no-pager
systemctl --user is-enabled chatgpt-remote-host.service
sudo sshd -T | grep -E 'clientalive(interval|countmax)|tcpkeepalive|usedns'
```

An answer in `198.18.0.0/15` for `controlplane.tailscale.com`, an Ubuntu NTP
pool, or `ntp-bootstrap.ubuntu.com` means the corresponding router exception is
missing or was not applied. Real answers were observed for all of them after
the fixes.

The expected family-safe desktop shape is a 600-second blanking delay, ambient
brightness off, idle dimming to 30%, screen locking off, both idle-suspend
actions set to `nothing` with zero-second disabled timeouts, and the power
button left `interactive` for GNOME. The three effective lid actions should be
`suspend`, while logind's ordinary idle action should be `ignore`. These fields
are read-only evidence; the diagnostic never blanks the panel, locks, suspends,
or changes a setting. The raw/max panel backlight values report the current
local choice, not a health threshold.

For the host thermal fields, values are millidegrees Celsius; compare the
package/composite input with its reported critical threshold rather than using
a generic laptop temperature cutoff. An NVMe `critical_warning` of zero, spare
above its threshold, and zero media errors are the healthy baseline. Wear and
unsafe-shutdown counters are cumulative observations: compare them across
checks, and do not label an old nonzero count as a new event without a prior
sample.

In the optional Beryl section, the expected healthy shape is one `tailscaled`,
one Mihomo `clash`, zero `netifyd`, and running Tailscale/OpenClash services.
`router_oom_kills_current_boot` is cumulative until the router reboots; it does
not imply that each invocation found a new OOM. `router_uptime_seconds` and
`router_latest_oom_age_seconds` use the router's monotonic boot clock, so the
latter can prove how long the current boot has survived since its most recent
OOM without depending on wall-clock parsing. It is `not_observed` when the
current boot has no matching OOM and `unknown` if the kernel-log timestamp
cannot be parsed. Compare the count, age, and process identity across checks.
The router probe is diagnostic only: it never restarts a service or changes a
router setting.

The Tailscale health note that some peers advertise routes while
`--accept-routes` is false is intentional on `big-red`: the Beryl advertises
`192.168.8.0/24`, but `big-red` is already physically attached to that same
LAN. Do not accept the duplicate route while the machine is on the Beryl LAN.

## MacBook behavior

At the time of the final check, `leos-macbook-air` was offline and did not
answer Tailscale pings. No Linux-side SSH change can make an asleep or offline
Mac respond.

Keep the existing Mac SSH alias with:

```sshconfig
Host big-red
    HostName big-red
    User leo
    IdentityFile ~/.ssh/id_ed25519_big_red
    IdentitiesOnly yes
    ProxyCommand /usr/local/bin/tailscale nc %h %p
    ServerAliveInterval 30
    ServerAliveCountMax 4
```

On the same Beryl LAN, `ssh leo@big-red.local` currently resolves through
Avahi/mDNS to `192.168.8.107`; use the Tailscale alias as the durable remote path.

The `ProxyCommand` bypasses Stash's competing `100.64.0.0/10` route. On the
Mac, keep Tailscale's `accept-dns` and `accept-routes` off while Stash owns
routing unless there is a deliberate migration.

If the Toronto Mac becomes an always-on host itself, keep it powered, awake,
online, and running the desktop app. A sleeping Mac stops both Tailscale and
ChatGPT Remote availability.

## Phone behavior

ChatGPT Remote does not require the phone's Tailscale VPN. iOS and Android
normally allow one active VPN tunnel at a time, so standalone Tailscale and
Stash can make each other appear intermittent. Use only the tunnel needed for
that task; keep ChatGPT Remote conceptually separate.

## Rollback

Router rollback:

1. Open **OpenClash → Overwrite Settings → DNS Settings**.
2. Remove only the affected exception group above (the seven
   Tailscale/connectivity patterns and/or the three Ubuntu NTP patterns), or
   disable the custom **Fake-IP-Filter** to roll the entire override back.
3. **Commit Settings**, then **Apply Settings**.
4. Confirm the previous profile is still selected.

Host rollback:

```bash
systemctl --user disable chatgpt-remote-host.service
sudo rm /etc/ssh/sshd_config.d/60-big-red-remote-reliability.conf
sudo systemctl reload ssh
```

The diagnostic command is read-only and can be left installed.

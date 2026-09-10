# Big Red Linux/Windows GPU dual mode

Big Red has one GPU, `0000:00:02.0` (Intel Arrow Lake, `8086:7d51`). Linux and the
`win11-starsector` VM cannot both own it. This is the reboot-based way to move it
between them.

The rule that shapes everything here: **the GPU only ever changes owner across a
reboot.** Nothing in this repository detaches a live GPU. On 2026-09-10 an implicit
detach took the machine down — `rpc-libvirtd` removed i915 and about five seconds
later a `JS Helper` exit faulted in `drm_framebuffer_cleanup` on kernel
`7.0.0-30-generic`. The dump is preserved at `/var/crash/202609100635/`.
[PR #40's guard](BIG_RED_WINDOWS_MOONLIGHT.md#gpu-start-guard) refuses that path;
this document is the supported way to satisfy the guard instead of bypassing it.

> **Windows mode works; the Wi-Fi adapter is what makes this machine hard to
> reach.** Both Windows/VFIO boots tested handed the GPU over correctly and ran
> the VM. The boot that appeared to "lose the host" was healthy the whole time --
> its Wi-Fi firmware had crashed, which is a fault that hits Linux boots just as
> often. See [What actually went wrong](#what-actually-went-wrong-in-test-5).

## The two modes

| | Default (Linux) | Explicit Windows |
|---|---|---|
| How you get there | any ordinary boot | `sudo big-red-boot-mode windows --reboot`, once |
| `0000:00:02.0` | `i915` | `vfio-pci`, bound in the initramfs |
| systemd target | `graphical.target` | `multi-user.target` |
| GDM | active | never started |
| Desktop access | GNOME Remote Desktop on 3389 | none (the VM owns the display path) |
| SSH, Tailscale, libvirt | up | up |
| `win11-starsector` | off | started once prerequisites are observed |
| Next boot after this one | Linux | Linux |

Windows mode is one-shot. `big-red-boot-mode windows` writes `next_entry` into
`/boot/grub/grubenv`; GRUB consumes and clears it while booting. A panic, a
`reboot`, a power cut, or a recovery-mode boot all land back on Linux. There is no
persistent Windows state to forget to undo.

## What is installed where

| Repository file | Host path | Purpose |
|---|---|---|
| `boot/grub.d/90-preflight-arc-vfio.cfg` | `/etc/default/grub.d/…` | default cmdline: IOMMU on, GPU left to i915 |
| `boot/grub.d/42_big_red_windows_mode` | `/etc/grub.d/…` | emits the one-shot Windows menu entry |
| `boot/modprobe.d/90-preflight-arc-vfio.conf` | `/etc/modprobe.d/…` | documents that no directive may live here |
| `boot/dracut.conf.d/90-preflight-arc-vfio.conf` | `/etc/dracut.conf.d/…` | ships VFIO modules without force-loading them |
| `scripts/big-red-boot-mode` | `/usr/local/sbin/…` | arm, clear, and report the next boot mode |
| `scripts/big-red-windows-mode-start` | `/usr/local/sbin/…` | observes prerequisites, then starts the VM |
| `scripts/big-red-handover-observe` | `/usr/local/bin/…` | read-only handover observation |
| `systemd/big-red-windows-mode.service` | `/etc/systemd/system/…` | runs the starter on a Windows boot only |
| `scripts/big-red-wait-for-tailnet` | `/usr/local/sbin/…` | waits for a Tailscale address, not just the daemon |
| `systemd/big-red-windows-moonlight-forward.service.d/wait-for-tailnet.conf` | `/etc/systemd/system/…` | drop-in that makes Sunshine forwarding wait for that address |

Install or re-verify with:

```bash
scripts/install-big-red-dual-mode --plan
scripts/install-big-red-dual-mode
scripts/install-big-red-dual-mode --verify-only
```

The installer refuses to run if PR #40's guard or libvirt hook has drifted from the
reviewed source, or if any VM is running. It backs up every file it replaces under
`/var/backups/big-red-dual-mode/<timestamp>/`, and it never touches `/var/crash`.

### Why the mode lives on the kernel command line

The September 3 configuration blacklisted `i915` and `xe` in `/etc/modprobe.d`,
force-loaded `vfio_pci` from `/etc/dracut.conf.d`, and put `vfio-pci.ids=` in the
default GRUB arguments. That made **every** boot a VFIO boot, including recovery, so
recovering a desktop required hand-unbinding the GPU at runtime — which is exactly
the operation that crashed the machine.

All four of those switches now live only on the one-shot entry:

```text
vfio-pci.ids=8086:7d51 rd.driver.pre=vfio_pci modprobe.blacklist=i915,xe \
initcall_blacklist=sysfb_init systemd.unit=multi-user.target bigred.mode=windows
```

`rd.driver.pre=vfio_pci` loads `vfio-pci` from the initramfs, which is where the
binding must happen: on this machine vfio-pci claims the device about 0.78 s into
boot, long before i915 could. The default entry keeps only `intel_iommu=on iommu=pt`,
which i915 is happy with (`[drm] VT-d active for gfx access`) and which means Windows
mode has nothing left to arrange at the last moment.

`systemd.unit=multi-user.target` is what keeps GDM inactive, rather than disabling
`gdm.service`. It is scoped to the single boot that asked for it, so the default boot
needs no repair, and the enablement state of GDM is never touched.

### Why Sunshine forwarding needed a drop-in

`big-red-windows-moonlight-forward.service` builds its nftables table from Big
Red's Tailscale IPv4, and it is ordered `After=tailscaled.service`. That orders it
after the daemon, not after the address. A Linux boot spends about 30s in userspace
and never lost that race; the Windows boot reaches `multi-user.target` in about 17s
and lost it immediately, failing with `no current Tailscale IPs; state: NoState`
about 4s into boot.

The drop-in adds an `ExecStartPre` that waits for `tailscale ip -4` to answer. It
changes nothing about the forwarding rules, and removing the drop-in restores the
previous behaviour exactly.

## Using it

Look first. This changes nothing:

```bash
big-red-handover-observe
```

It reports GPU driver ownership, the graphical-session state, which processes hold
the GPU's DRM nodes, the VM's state, the IOMMU group, and whether SSH and Tailscale
are still there to get you back out. It reports observations, not verdicts, and it
runs only query commands — the test suite parses the source to prove that.

Go to Windows for one boot:

```bash
sudo big-red-boot-mode windows --reboot
```

This refuses unless the VM is shut off, the guard is installed, the Windows entry is
in `grub.cfg`, the starter unit is enabled, and both `ssh.service` and
`tailscaled.service` are active. It verifies the arming landed in `grubenv` before it
reboots.

Come back to Linux — just reboot:

```bash
sudo systemctl reboot
```

To cancel an arming without rebooting: `sudo big-red-boot-mode linux`.

## When Windows mode refuses

`big-red-windows-mode.service` starts the domain only after observing all of:
`0000:00:02.0` bound to `vfio-pci`, no DRM nodes on that device, IOMMU group holding
nothing but the GPU, `gdm.service` confirmed inactive, `ssh.service` and
`tailscaled.service` active, and `win11-starsector` shut off.

If any of those is missing, it exits non-zero and the unit is left `failed` on
purpose. Nothing depends on it, so the boot still completes and the host stays
reachable. Read the reason and reboot:

```bash
systemctl status big-red-windows-mode.service
big-red-handover-observe
sudo systemctl reboot
```

Do not respond to a refusal by unbinding the GPU by hand, by `virsh nodedev-detach`,
or by writing `driver_override`. A refusal means the reboot did not produce the state
the VM needs; another reboot is the cheap, safe answer.

## Recovery

Keep a second SSH session open on the Beryl path during every mode switch. It does
not depend on Big Red's own Tailscale transport:

```bash
ssh big-red-beryl
```

- **Windows mode came up but the VM did not start.** The host is on `multi-user.target`
  with SSH and Tailscale up. Read `systemctl status big-red-windows-mode.service`, then reboot.
- **A boot fails outright.** GRUB has already cleared the one-shot arming, so the next
  boot is Linux. Power-cycle if needed.
- **You need a Linux boot with nothing extra.** The recovery entries under *Advanced
  options for Ubuntu* never carry `GRUB_CMDLINE_LINUX_DEFAULT`, so they carry no VFIO
  arguments and no `bigred.mode=`.
- **You want the September 3 configuration back.** Restore from the newest directory
  under `/var/backups/big-red-dual-mode/`, then `sudo update-initramfs -u -k all` and
  `sudo update-grub`.

## Tests

```bash
python3 tests/test-big-red-dual-mode.py
python3 tests/test-big-red-vm-gpu-guard.py
```

## Observed results

Measured on 2026-09-10 (host clock `Asia/Shanghai`, so 02:0x CST the next day) on
kernel `7.0.0-31-generic`. Times are from the moment the reboot command returned.
Host-side offsets come from `systemd-analyze` and each unit's
`ActiveEnterTimestampMonotonic`, which are exact; the client-observed column also
contains shutdown, firmware, Wi-Fi association and Tailscale re-establishment.

| | 1: Linux | 2: Windows one-shot | 3: back to Linux | 4: Linux steady state | 5: Windows again |
|---|---|---|---|---|---|
| preceded by | hand-rescued session | test 1 | test 2 | test 3 | test 4 |
| client SSH (independent Beryl path) | 233s | 35s | 114s | 45s | never |
| client SSH (Tailscale direct) | 244s | 30s | 131s | 40s | never |
| client usable (desktop / VM running) | 249s | 39s | 135s | 50s | never |
| kernel start → `sshd` | 25.4s | 4.0s | 25.4s | 4.4s | — |
| kernel start → GDM / VM start | 19.5s | 16.9s | 9.7s | 7.7s | — |
| total `systemd-analyze` | 38.3s | 23.3s | 39.4s | 16.8s | — |
| Wi-Fi DHCP lease at | 205.1s | 7.2s | 98.8s | 7.5s | never |
| `nl80211` interface-UP timeouts | 5 | 0 | 5 | 0 | — |

### What each test showed

**Test 1, default Linux boot.** The default entry carried no VFIO arguments, `i915`
claimed `0000:00:02.0`, `driver_override` came back empty (the hand-rescue artifact
cleared by the reboot), `graphical.target` was the default, GDM was active, RDP was
listening on 3389 and a seated session existed.

**Test 2, one-shot Windows boot.** `vfio-pci` claimed the GPU at **0.785s**, before
anything else could. The device exposed no DRM node and nothing held one. GDM was
never started: `systemctl is-active gdm.service` returned `inactive` with exit 3,
which is exactly what PR #40's guard requires. `big-red-windows-mode.service`
observed the prerequisites and started the domain; the guest was online in the
tailnet 59s after the reboot. `grubenv` showed `next_entry=` — the one-shot was
consumed by GRUB. SSH was accepting connections 4.0s into the boot.

**Test 3, return to Linux.** The guest shut down gracefully in 22s. A plain reboot
returned to `i915`, GDM and RDP with nothing armed.

**Test 4, steady-state Linux reboot.** The fastest boot measured: `sshd` at 4.4s,
desktop at 10.4s, 16.8s total.

**Test 5, second Windows boot — unreachable, but not broken.** The handover
succeeded and the VM ran for two hours; the Wi-Fi adapter firmware crashed, so the
host had no network and needed a physical power cycle to get it back. See below.

### Zero live detachments

No step in this sequence wrote `driver_override`, wrote to `unbind` or
`drivers_probe`, ran `virsh nodedev-detach`, or stopped a running GDM. Every change
of GPU ownership happened across a reboot. `/var/crash/202609100635/` was
fingerprinted before the work (`280474` and `771324316` bytes) and verified
unchanged after every install.

### What actually went wrong in test 5

The first diagnosis in this file was wrong and is corrected here. Test 5 was
recorded as a possible hang in the passthrough device reset. It was not. The
machine booted, ran for 2h18m, and was shut down only by a physical power cycle.

The Windows boot itself did everything it was supposed to:

```text
[0.760] vfio-pci 0000:00:02.0: vgaarb: deactivate vga console
[0.760] vfio_pci: add [8086:7d51[ffffffff:ffffffff]] class 0x000000/00000000
02:29:35  Reached target multi-user.target
02:29:35  Prerequisites observed: 0000:00:02.0 on vfio-pci, GDM inactive, win11-starsector shut off.
02:29:35  Domain 'win11-starsector' started
```

The guest then renewed its DHCP lease every ~27 minutes until 04:20, so it was
alive and well for two hours. GDM never started. The one-shot arming was already
consumed. Nothing about the GPU handover failed.

What failed was the **Wi-Fi adapter firmware**:

```text
[4.551] iwlwifi 0000:00:14.3: 0x00000071 | NMI_INTERRUPT_UMAC_FATAL
[5.706] iwlwifi 0000:00:14.3: HW error, resetting before reading
```

14 hardware errors and 92 fatal firmware assertions, never recovering. The host
had no network, so both SSH paths were dead while the machine sat there working.

### The real availability risk: iwlwifi, not the GPU

Counting `NMI_INTERRUPT_UMAC_FATAL` across every boot the journal still holds:

| boot | when | mode | fatal FW errors | Wi-Fi lease |
|---|---|---|---|---|
| -12 … -10 | 08-31 → 09-03 | Linux | 0 | ~8s |
| -9, -8 | 09-10 06:35 | kdump + recovery | 7, 91 | never |
| -7, -6 | 09-11 01:13, 01:15 | Linux | 0 | ~7.6s |
| -5 | test 1 | Linux | 82 | 205s |
| -4 | test 2 | **Windows** | 0 | 7.2s |
| -3 | test 3 | Linux | 79 | 98.8s |
| -2 | test 4 | Linux | 0 | 7.5s |
| -1 | test 5 | **Windows** | 92 | never |
| 0 | recovery (cold boot) | Linux | 0 | 8.6s |

Two things follow, and neither involves the GPU:

1. **The fault is mode-independent.** It hit two Linux boots and one Windows boot,
   and spared another Windows boot. Windows mode is 2-for-2 on handing over the GPU.
2. **It began with the 2026-09-10 kernel crash.** Every boot before that is clean;
   the crash-recovery boot logged 91 fatal errors and it has recurred since.

From test 1 onward the failures alternate perfectly -- broken, clean, broken,
clean, broken, clean. Six samples alternating is suggestive but not proof (about
a 3% coincidence), and no mechanism for the alternation has been established. It
is worth more samples, and they are cheap: repeated Linux reboots test it with no
GPU risk at all.

Recovery is also inconsistent: sometimes the adapter comes back after 99-205s,
sometimes never. `sshd` is listening at ~4s regardless, so when the adapter dies
the machine is healthy and simply unreachable.

**This is the thing to fix before trusting remote reboots of any kind** -- and a
watchdog would not have helped, because the host was never hung.

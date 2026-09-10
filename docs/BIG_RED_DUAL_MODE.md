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

<!-- filled in from the real reboot sequence -->

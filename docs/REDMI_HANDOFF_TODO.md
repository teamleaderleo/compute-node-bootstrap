# REDMI bootstrap and Codex takeover

## Preferred plan: owner and Codex together in person

The owner will physically hold the REDMI Book and work through the setup with Codex. Mom does not need to prepare Windows, create USB media or install Ubuntu.

1. Connect the 128 GB USB stick to the Mac or the REDMI Book.
2. Let Codex identify the exact USB device before writing the Ubuntu image.
3. Boot the REDMI Book into Windows once and inspect the actual hardware and firmware state.
4. Create the Ubuntu USB using the illustrated guide.
5. Boot **Try Ubuntu** and test the hardware.
6. Install Ubuntu with username `leo` and computer name `redmi-01`.
7. Connect Ubuntu to the residential Wi-Fi and join Tailscale.

From the first Windows screen onward, the owner can show Codex photos/screenshots and follow one step at a time. The point where Codex can operate the REDMI directly, instead of guiding the local screen, is the first successful shell from the Mac:

```bash
ssh leo@redmi-01
```

Ubuntu does not need to be fully configured before this shell works. Everything after it can be completed remotely.

## Standard names

- Ubuntu username: `leo`
- computer name: `redmi-01`
- first remote connection: Tailscale SSH

## Before the REDMI arrives

- [x] Obtain a USB stick for Ubuntu: a 128 GB stick has been purchased.
- [ ] Decide whether factory Windows recovery is wanted; if yes, obtain a second 32 GB or larger USB stick. Otherwise the single 128 GB stick is enough.
- [ ] Have the REDMI Book, charger, USB stick and Mac together.

The operator Mac is already prepared: Tailscale and Stash can run together, the Mac does not accept tailnet DNS or subnet routes, and no exit node is selected.

## Earliest remote-shell handoff

1. Follow the illustrated [中文](../machines/redmibook-pro-16-2025/INSTALL.zh-CN.md) or [English](../machines/redmibook-pro-16-2025/INSTALL.md) guide.
2. Install Ubuntu with username `leo` and computer name `redmi-01`.
3. Connect the installed Ubuntu system to the residential Wi-Fi.
4. Paste the guide's OpenSSH and Tailscale command block into Terminal.
5. Run `sudo tailscale up --ssh --hostname=redmi-01`.
6. Send the displayed Tailscale authentication URL to the operator.
7. Confirm that `ssh leo@redmi-01` works from the Mac.

That is the end of the setup that requires the REDMI's keyboard and screen.

## What the operator/Codex does at first contact

- [ ] Open the Tailscale authentication URL and add `redmi-01` to the existing tailnet.
- [ ] Confirm `redmi-01` is online in the Tailscale machine list.
- [ ] Disable Tailscale key expiry for `redmi-01`.
- [ ] Connect with `ssh leo@redmi-01`.
- [ ] Confirm that direct remote operation has begun.

## What Codex handles after the handoff

- [ ] Record the actual model, firmware, CPU, memory, storage, network and kernel state.
- [ ] Install Ubuntu updates and the baseline packages from this repository.
- [ ] Confirm time synchronization and the `Asia/Shanghai` timezone.
- [ ] Configure automatic security updates.
- [ ] Add the operator's conventional `redmi-01` SSH key and verify a second remote login path.
- [ ] Configure AC-power, lid-close and suspend behavior for unattended operation.
- [ ] Set a supported battery charge ceiling after inspecting the hardware's actual Linux interface.
- [ ] Enable Linux IP forwarding and advertise `redmi-01` as a Tailscale exit node.
- [ ] Approve the exit-node routes in Tailscale.
- [ ] Reboot once and verify that networking, Tailscale and remote access return automatically.
- [ ] Select `redmi-01` as the Beryl's Custom Exit Node only after the REDMI side is healthy.
- [ ] Test the Beryl path with a non-work device, including DNS and public egress.
- [ ] Verify that disabling Custom Exit Node restores the existing OpenClash/Bandwagon path.
- [ ] Update the repository with the actual REDMI and end-to-end observations.

CI runner registration and workload-specific tooling come after the residential exit-node path and remote recovery have been proven.

## If Mom has to do it instead

The same illustrated guide still supports a video-call handoff. Her final task would be sending the Tailscale authentication URL and waiting until the operator confirms `ssh leo@redmi-01` works. This is now the fallback rather than the primary plan.

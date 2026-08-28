# REDMI handoff: the earliest point Codex can take over

The physical handoff is complete when the operator successfully reaches this shell from the Mac:

```bash
ssh leo@redmi-01
```

At that point, the person holding the REDMI Book can walk away. Ubuntu does not need to be fully configured first.

## Standard names

- Ubuntu username: `leo`
- computer name: `redmi-01`
- first remote connection: Tailscale SSH

## Before the REDMI arrives

- [ ] Obtain a 16 GB or larger USB stick for Ubuntu.
- [ ] Obtain a 32 GB or larger USB stick if a factory Windows recovery drive is wanted.
- [ ] Keep the [中文安装指南](../machines/redmibook-pro-16-2025/INSTALL.zh-CN.md) ready to send.
- [ ] Be available to open the Tailscale authentication link when the laptop reaches that step.

The operator Mac is already prepared: Tailscale and Stash can run together, the Mac does not accept tailnet DNS or subnet routes, and no exit node is selected.

## What the person holding the laptop does

1. Follow the illustrated [中文](../machines/redmibook-pro-16-2025/INSTALL.zh-CN.md) or [English](../machines/redmibook-pro-16-2025/INSTALL.md) guide.
2. Install Ubuntu with username `leo` and computer name `redmi-01`.
3. Connect the installed Ubuntu system to the residential Wi-Fi.
4. Paste the guide's OpenSSH and Tailscale command block into Terminal.
5. Run `sudo tailscale up --ssh --hostname=redmi-01`.
6. Send the displayed Tailscale authentication URL to the operator.
7. Stay near the laptop until the operator confirms that `ssh leo@redmi-01` works.

That is the end of the physical setup.

## What the operator/Codex does at first contact

- [ ] Open the Tailscale authentication URL and add `redmi-01` to the existing tailnet.
- [ ] Confirm `redmi-01` is online in the Tailscale machine list.
- [ ] Disable Tailscale key expiry for `redmi-01`.
- [ ] Connect with `ssh leo@redmi-01`.
- [ ] Tell the person holding the laptop that the handoff is complete.

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

## The part that cannot be handed off earlier

Someone physically present must power on the laptop, boot the USB, operate the Ubuntu installer and connect the installed system to Wi-Fi. Before Ubuntu and Tailscale are online, there is no remote shell for Codex to use.

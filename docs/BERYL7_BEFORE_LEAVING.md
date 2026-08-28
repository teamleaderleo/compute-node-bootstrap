# Beryl 7: do this before leaving

This checklist is for the **GL.iNet Beryl 7 (GL-MT3600BE)** — the mint-green Wi‑Fi 7 travel router.

Goal for today: **join the router to Tailscale without changing the existing OpenClash/Bandwagon traffic path.** The REDMI exit-node migration can happen later.

## 1. Confirm the model and firmware

Open the GL.iNet admin panel (normally `http://192.168.8.1`).

Check that the model is **GL-MT3600BE / Beryl 7**.

Go to **SYSTEM → Upgrade** and note the current firmware version.

If **APPLICATIONS → Tailscale** already exists, there is no reason to upgrade firmware right before travel. Keep the working firmware.

## 2. Back up the current router configuration

Because the router already has an OpenClash/VPS setup worth preserving, make a backup before changing anything.

In the GL.iNet UI:

1. **SYSTEM → Advanced Settings**.
2. Open **LuCI**.
3. **System → Backup / Flash Firmware**.
4. Under **Backup**, click **Generate archive**.
5. Save the downloaded archive somewhere you can find later.

Also save/export the current OpenClash profile/YAML separately if OpenClash provides an export/download option.

> GL.iNet notes that a LuCI backup is tied to the firmware version it came from. Keep the firmware version written down next to the archive.

## 3. Create/sign into the Tailscale account

Open the Tailscale admin console in your own browser and sign in.

You do **not** need to install Tailscale on the work computer.

If you want to test tailnet connectivity from your Mac before leaving, install Tailscale on the Mac as well. This is optional for merely enrolling the router.

## 4. Join the Beryl 7 to Tailscale

In the GL.iNet web UI:

1. Go to **APPLICATIONS → Tailscale**.
2. Enable **Tailscale**.
3. Click **Apply**.
4. Wait for **Device Bind Link** to appear.
5. Open the bind link.
6. Sign into your Tailscale account and approve/connect the Beryl 7.
7. Return to the GL.iNet page and confirm Tailscale shows connected.
8. In the Tailscale admin console, confirm the Beryl 7 appears online.

## 5. Stop there today

For the pre-departure setup, leave these alone:

- **Custom Exit Nodes: off**;
- **Run Exit Node: off**;
- **Advertise LAN/WAN subnets: off** unless you already have a specific reason to use them;
- OpenClash/Bandwagon routing unchanged;
- existing work-computer traffic unchanged.

This means enabling Tailscale should only add the router itself to the tailnet. It should not replace the current internet route.

## 6. Quick sanity test

After enabling Tailscale:

- verify ordinary browsing still works through the router;
- verify OpenClash/VPS behavior still works exactly as before;
- check the Tailscale admin console and confirm the Beryl 7 remains online.

If you installed Tailscale on your Mac, you can also test access to the router over its Tailscale IP / MagicDNS name.

## 7. What happens after the REDMI arrives

Later:

1. install Ubuntu 26.04 on `redmi-01`;
2. join `redmi-01` to the same tailnet;
3. advertise `redmi-01` as an exit node;
4. approve it in Tailscale;
5. on the Beryl 7, enable **Custom Exit Nodes** and choose `redmi-01`;
6. test with a non-work device first;
7. only after that, decide whether to route the work computer through the REDMI.

The existing OpenClash/Bandwagon path stays available as the rollback until the new path has been proven.

## One caution about OpenClash

GL.iNet explicitly warns that Tailscale can conflict with some other router VPN/routing features because they can all modify routes/firewall rules. OpenClash is a third-party OpenWrt routing/proxy package and is not named in GL.iNet's built-in conflict list, but it also modifies routing/DNS/firewall behavior.

That is why today's safe setup is **enroll the Beryl in Tailscale without selecting an exit node or changing traffic policy**. Test coexistence before migrating real work traffic.

## Official references

- GL.iNet Tailscale guide: https://docs.gl-inet.com/router/en/4/interface_guide/tailscale/
- Beryl 7 product page: https://www.gl-inet.com/products/gl-mt3600be
- GL.iNet backup/upgrade guide: https://docs.gl-inet.com/router/en/4/tutorials/how_to_upgrade_downgrade_router/

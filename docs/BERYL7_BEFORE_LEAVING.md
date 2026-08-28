# Beryl 7: do this before leaving

This checklist is for the **GL.iNet Beryl 7 (GL-MT3600BE)** — the mint-green Wi‑Fi 7 travel router.

Goal for today: **join the router to Tailscale without changing the existing OpenClash/Bandwagon traffic path.** The REDMI exit-node migration can happen later.

## Observed state on 2026-08-28

Issue #1 was carried out against the actual router with these results:

- model: **GL.iNet GL-MT3600BE / Beryl 7**;
- GL.iNet firmware: **4.9.0**;
- OpenWrt/kernel: **OpenWrt 21.02-SNAPSHOT / Linux 5.4.281**;
- normal LAN admin address: **`192.168.8.1`**;
- upstream connection: Ethernet WAN using DHCP from the ZTE/Big Brouter network;
- built-in Tailscale: present as a **Beta** feature, running Tailscale **1.92.5**;
- tailnet device name: **`gl-mt3600be`**, confirmed online;
- Tailscale device-key expiry: disabled for this long-lived router;
- GoodCloud: disabled;
- Custom Exit Node, Run Exit Node, WAN/LAN subnet advertisement and IP Masquerading: all left off.
- after returning the Mac to Big Brouter, connection attempts to the Beryl WAN address on ports 22, 80 and 443 timed out; router administration remained available only from the Beryl LAN in this test.

The complete LuCI configuration archive was generated before Tailscale was enabled. It includes the OpenClash configuration, active profiles, custom files, overrides, history and rule providers. Because the archive contains credentials, its exact absolute path and checksum are kept in the operator's local-only backup directory and handoff notes, not in Git.

OpenClash remained running after the router joined Tailscale. The observed baseline was OpenClash `v0.47.133`, Mihomo `v1.19.29 Meta`, Fake-IP Enhance + Rule mode, with `beryl7-openclash-cn-direct-v2.yaml` selected. The router-side checks continued to show the existing U.S./Los Angeles Akamai/Linode egress and normal connectivity.

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

When Stash or another proxy is also running on the test Mac, its public-IP result may show the Mac proxy's egress rather than OpenClash's egress. For the 2026-08-28 verification, the OpenClash status page was the authoritative router-side check; the Mac briefly showed a different U.S. region while double-proxied.

## Troubleshooting notes from the actual setup

- Connect to the normal `MinistryOfRouting` SSID and wait for a `192.168.8.x` DHCP lease before opening `192.168.8.1`. On the first attempt, macOS briefly reported the SSID as connected but fell back to Big Brouter before DHCP completed; reconnecting once succeeded.
- On this firmware, LuCI is reachable locally at `http://192.168.8.1/cgi-bin/luci/` (and the router also exposes the local LuCI service on port 8080). If **Go To LuCI** does not open a tab, use the local URL directly.
- LuCI may show a harmless **No related RPC reply** dialog while the underlying page still works. Dismiss the dialog before clicking **Generate archive** or reading OpenClash status.
- A browser download may retain a temporary `.crdownload` filename even after the archive is complete. Do not trust the extension: verify it with `gzip -t`, list it with `tar -tzf`, then copy it into the restricted local backup directory with mode `600`.
- The GL.iNet Device Bind Link banner was transient. If it disappears, use LuCI's local Web Console and run `tailscale status --peers=false` to obtain the one-time login link. Treat that link as a credential: do not paste it into Git, issue comments, screenshots or logs.
- After approving the device, verify locally with `tailscale status --json`: `BackendState` should be `Running`, `Self.Online` should be true, and a Tailscale IP should exist. Also verify that exit-node selection and advertised routes are empty.
- Enrolling the router itself coexisted with the current OpenClash setup in this test. That does **not** prove that OpenClash and a Tailscale exit node will compose safely; the exit-node path remains a separate later test.
- On the test Mac, enabling Tailscale while Stash was using the Oregon Hysteria2 profile initially broke that proxy path. The Mac's Tailscale preferences were accepting tailnet DNS and advertised routes. Running `tailscale set --accept-dns=false --accept-routes=false` removed the overlap: Stash and Tailscale then remained connected simultaneously, Oregon stayed the public egress, ordinary HTTP succeeded, and the Mac reached `gl-mt3600be` over Tailscale. This changes only the Mac client; it does not select an exit node or change the Beryl's routing.
- iOS and Android allow only one active VPN app at a time. A phone running standalone Tailscale and Stash should therefore use only one at a time; Tailscale On Demand can otherwise make the conflict seem intermittent. The future Beryl-to-REDMI design does not require Tailscale on the phone or work computer. Recent Stash versions also offer a built-in Tailscale node for an optional single-tunnel setup, but that was not configured or tested here.

## 7. What happens after the REDMI arrives

Use the illustrated [English](../machines/redmibook-pro-16-2025/INSTALL.md) or [中文](../machines/redmibook-pro-16-2025/INSTALL.zh-CN.md) laptop handoff guide.

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
- Tailscale coexistence with other VPNs: https://tailscale.com/docs/reference/faq/other-vpns
- Stash built-in Tailscale: https://stash.wiki/en/features/nat-traversal

# GL.iNet Beryl 7 → REDMI exit node

This is the clean path for a computer that **cannot or should not install Tailscale itself**.

The router in this setup is the **GL.iNet Beryl 7 (GL-MT3600BE)**, the mint-green Wi‑Fi 7 travel router. GL.iNet's current firmware documents this model as Tailscale-supported.

The network path is:

```text
work laptop
    ↓ Wi-Fi / Ethernet
Beryl 7 (GL-MT3600BE)
    ↓ Tailscale
redmi-01 (exit node)
    ↓
internet
```

The work laptop only sees an ordinary Wi-Fi/Ethernet connection. The Beryl 7 carries its traffic through the REDMI Book.

## Before changing the current working router

If the router already has OpenClash/YAML routing through a Bandwagon VPS, preserve it until the REDMI path is proven.

See [Beryl 7: do this before leaving](BERYL7_BEFORE_LEAVING.md) for the low-risk first step: enroll the router in Tailscale **without** selecting an exit node or altering current traffic routing.

## Why this is useful

If the current setup uses a router-side YAML/proxy profile pointing at a rented VPS, the Beryl 7's built-in Tailscale support may let us replace that VPS endpoint for this use case.

The REDMI Book becomes the exit node, and the Beryl 7 chooses it as a **Custom Exit Node**. Devices connected to the router then appear to the public internet as coming from the REDMI Book's internet connection/location.

Important: the public exit location is wherever `redmi-01` is physically connected at that moment. If it is in China, traffic exits in China; if it later lives in Vancouver, traffic exits there.

## GL.iNet support

Current GL.iNet Router Docs list **GL-MT3600BE (Beryl 7)** among the models with built-in Tailscale support.

Official reference:

https://docs.gl-inet.com/router/en/4/interface_guide/tailscale/

## REDMI side: advertise an exit node

First complete the illustrated [English](../machines/redmibook-pro-16-2025/INSTALL.md) or [中文](../machines/redmibook-pro-16-2025/INSTALL.zh-CN.md) REDMI Book handoff guide.

After Tailscale is already working on `redmi-01`, enable Linux IP forwarding:

```bash
printf '%s\n' \
  'net.ipv4.ip_forward = 1' \
  'net.ipv6.conf.all.forwarding = 1' \
  | sudo tee /etc/sysctl.d/99-tailscale-exit-node.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale-exit-node.conf
```

Then advertise the REDMI Book as an exit node:

```bash
sudo tailscale set --advertise-exit-node
```

In the Tailscale admin console, approve `redmi-01` for **Use as exit node**.

Official reference:

https://tailscale.com/docs/features/exit-nodes/how-to/setup

## Beryl 7 side

In the router web admin UI:

1. Open **APPLICATIONS → Tailscale**.
2. Confirm the router is joined to the same tailnet as `redmi-01`.
3. Enable **Custom Exit Nodes**.
4. Refresh the exit-node list.
5. Select `redmi-01` / its Tailscale IP.
6. Apply.

GL.iNet's current docs say devices connected to the router then route their public internet traffic through the chosen exit node.

If LAN clients lose internet after selecting the exit node, first check that the Beryl 7's required subnet routes are approved in the Tailscale admin console. Current GL.iNet firmware also exposes IP Masquerading support for Tailscale, which is useful for LAN clients that do not themselves run Tailscale.

## Work-computer behavior

Nothing is installed on the work computer.

It simply connects to the Beryl 7. Depending on the router's policy configuration, we can route:

- every connected device through `redmi-01`;
- only the work computer;
- selected traffic through the REDMI while leaving other traffic on the ordinary route.

The exact policy should be tested first with a non-work device.

## Relationship to the existing YAML/VPS setup

Do not delete the existing VPS/YAML configuration until the Tailscale path has been tested.

There are two different designs:

### Existing proxy design

```text
work laptop → Beryl 7 → OpenClash/YAML proxy → Bandwagon VPS → internet
```

To point that same YAML at the REDMI Book, the REDMI Book would have to run the **same proxy protocol/server** expected by the YAML and be reachable by the router. That can work, but it preserves another application-layer proxy service to maintain.

### Router + Tailscale exit-node design

```text
work laptop → Beryl 7 → Tailscale → REDMI → internet
```

This is simpler when the goal is merely to make the Beryl-connected device use the REDMI Book as its internet egress. No proxy client is required on the work laptop and no public inbound port is required on the REDMI Book.

## Migration protocol

1. Keep the current Bandwagon/OpenClash profile working.
2. Join the Beryl 7 to the tailnet without changing its current route.
3. Bring `redmi-01` into the same tailnet.
4. Advertise/approve `redmi-01` as an exit node.
5. Select `redmi-01` as the Beryl 7 Custom Exit Node.
6. Connect a non-work test device to the router first.
7. Verify its public IP matches the REDMI Book's connection.
8. Test DNS, corporate VPN, video calls and other work-sensitive traffic.
9. Only then decide whether the old VPS/YAML path is still useful as a fallback.

## OpenClash coexistence warning

GL.iNet explicitly warns that Tailscale can conflict with some other VPN/routing features because they modify the same routing/firewall state. OpenClash is a third-party OpenWrt proxy/routing package, so treat simultaneous OpenClash + Tailscale exit-node routing as something to **test deliberately** rather than assume will compose perfectly.

Keep the existing profile as rollback while testing.

## Actual Beryl 7 baseline (2026-08-28)

The real Beryl 7 was enrolled before `redmi-01` existed. The observed baseline is:

- GL-MT3600BE running GL.iNet firmware 4.9.0;
- built-in Tailscale 1.92.5 online as `gl-mt3600be`;
- no Custom Exit Node selected;
- Run Exit Node off;
- no WAN or LAN subnets advertised;
- IP Masquerading off;
- OpenClash/Mihomo still running with the same selected Bandwagon profile and modes;
- ordinary LAN/admin access and internet access still working.

This proves only that basic tailnet membership coexists with the current OpenClash setup. It does not prove the future Tailscale exit-node route. Keep the Bandwagon/OpenClash path unchanged until `redmi-01` is online and the full path has passed the non-work-device test.

The router's Tailscale enrollment banner was not reliable during setup: it appeared once and then disappeared, while the daemon still needed authentication. LuCI's local Web Console provided the one-time login URL and the final daemon status. Never record that login URL. The successful final checks were `BackendState: Running`, the router online in the Tailscale device list, an assigned Tailscale IP, an empty exit-node ID and no advertised routes.

When `redmi-01` arrives, record the current OpenClash state and public egress again before changing the Beryl. Then select `redmi-01` only after the REDMI has advertised the exit-node routes and they have been approved in Tailscale. Test with a non-work device first and confirm:

1. the test device's public IP matches the REDMI connection;
2. DNS resolution and leak behavior are acceptable;
3. the corporate VPN, video calls and other work-sensitive traffic behave normally;
4. disabling Custom Exit Node immediately restores the existing OpenClash/Bandwagon path.

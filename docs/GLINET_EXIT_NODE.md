# GL.iNet router → REDMI exit node

This is the clean path for a computer that **cannot or should not install Tailscale itself**.

The network path is:

```text
work laptop
    ↓ Wi-Fi / Ethernet
GL.iNet router
    ↓ Tailscale
redmi-01 (exit node)
    ↓
internet
```

The work laptop only sees an ordinary Wi-Fi/Ethernet connection. The GL.iNet router carries its traffic through the REDMI Book.

## Why this is useful

If the current setup uses a router-side YAML/proxy profile pointing at a rented VPS, a GL.iNet model with current Tailscale support may let us replace that whole VPS endpoint for this use case.

The REDMI Book becomes the exit node, and the GL.iNet router chooses it as a **Custom Exit Node**. Devices connected to the router then appear to the public internet as coming from the REDMI Book's internet connection/location.

Important: the public exit location is wherever `redmi-01` is physically connected at that moment. If it is in China, traffic exits in China; if it later lives in Vancouver, traffic exits there.

## GL.iNet support

GL.iNet firmware 4 includes a Tailscale application on many recent models. Current GL.iNet documentation specifically supports **Custom Exit Nodes** and routing LAN clients through them.

Common supported travel/small-router models include:

- GL-MT3000 (Beryl AX)
- GL-AXT1800 (Slate AX)
- GL-A1300 (Slate Plus)
- GL-MT2500 / MT2500A (Brume 2)
- GL-MT6000 (Flint 2)

Several older models are unsupported, so confirm the exact model before changing the existing setup.

Official reference:

https://docs.gl-inet.com/router/en/4/interface_guide/tailscale/

## REDMI side: advertise an exit node

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

## GL.iNet side

In the router web admin UI:

1. Open **APPLICATIONS → Tailscale**.
2. Join the router to the same tailnet.
3. In the Tailscale admin console, approve the router's advertised subnet route if the firmware asks for it.
4. Back in the GL.iNet UI, enable **Custom Exit Nodes**.
5. Refresh the exit-node list.
6. Select `redmi-01` / its Tailscale IP.
7. Apply.

On firmware 4.9+, GL.iNet also documents **IP Masquerading**, which can simplify forwarding LAN clients through Tailscale when those clients cannot install Tailscale themselves.

## Work-computer behavior

Nothing is installed on the work computer.

It simply connects to the GL.iNet router. Depending on the router's policy configuration, we can route:

- every connected device through `redmi-01`; or
- only the work computer; or
- only selected domains/IPs through the routed path.

GL.iNet's VPN policy modes can target a client device by MAC address, so a work laptop can be routed differently from other devices connected to the same router.

## Relationship to the existing YAML/VPS setup

Do not delete the existing VPS/YAML configuration until the Tailscale path has been tested.

There are two different designs:

### Existing proxy design

```text
work laptop → GL.iNet → proxy described by YAML → Bandwagon VPS → internet
```

To point that same YAML at the REDMI Book, the REDMI Book would have to run the **same proxy protocol/server** expected by the YAML and be reachable by the router. That can work, but it preserves another application-layer proxy service to maintain.

### Router + Tailscale exit-node design

```text
work laptop → GL.iNet → Tailscale → REDMI → internet
```

This is simpler when the goal is merely to make the GL.iNet-connected device use the REDMI Book as its internet egress. No proxy client is required on the work laptop and no public inbound port is required on the REDMI Book.

## Migration protocol

1. Keep the current Bandwagon/VPS profile working.
2. Confirm the GL.iNet model/firmware supports Tailscale and Custom Exit Nodes.
3. Bring `redmi-01` into the tailnet.
4. Advertise/approve it as an exit node.
5. Join the GL.iNet router to the same tailnet.
6. Select `redmi-01` as Custom Exit Node.
7. Connect a non-work test device to the router first.
8. Verify its public IP matches the REDMI Book's connection.
9. Test DNS, corporate VPN, video calls and other work-sensitive traffic.
10. Only then decide whether the old VPS/YAML path is still useful as a fallback.

## One warning

GL.iNet currently warns that its Tailscale feature can conflict with other router VPN clients such as OpenVPN, WireGuard Client, ZeroTier and some GL.iNet tunneling features when used simultaneously.

If the existing YAML setup is implemented by a third-party proxy package rather than GL.iNet's VPN client, test carefully rather than assuming both routing systems can be active at once.

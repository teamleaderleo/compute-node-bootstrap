# Remote access

For the REDMI Book, the preferred first remote-control path is **Tailscale SSH**, with ordinary OpenSSH installed as a fallback.

## Preferred path: Tailscale SSH

Why this is attractive for a laptop behind a residential router:

- no router port forwarding;
- no public port 22;
- no dynamic DNS;
- the Tailscale address/hostname stays stable when the machine changes networks;
- no manual SSH public-key distribution is required for Tailscale SSH;
- the operator can authenticate the new node into the tailnet from their own browser.

The family-facing install guide contains the exact copy/paste blocks.

After Tailscale is installed on the node:

```bash
sudo tailscale up --ssh --hostname=redmi-01
```

That command prints a `https://login.tailscale.com/...` authentication URL. The person physically holding the node sends that URL privately to the operator. The operator opens it and authenticates the node into their tailnet.

From the operator's machine, which must also be signed into the same tailnet:

```bash
ssh UBUNTU_USERNAME@redmi-01
```

If the tailnet still uses Tailscale's default access-control policy, its default Tailscale SSH policy allows a user to connect to their own devices. If the tailnet ACL/policy has been customized, verify that it permits both network access and Tailscale SSH access to this node.

## Why there is still an OpenSSH server

The install guide also installs `openssh-server` and enables it.

Tailscale SSH only intercepts SSH traffic arriving through the Tailscale address. Normal OpenSSH can still serve LAN or other deliberately configured paths, so keeping it installed gives us a second recovery mechanism.

If we later decide to use ordinary SSH authentication, the operator can generate an Ed25519 key pair on their own machine:

```bash
ssh-keygen -t ed25519
```

Only the public key belongs on the REDMI Book. The private key never leaves the operator's machine. This can all be configured remotely after the first Tailscale SSH session, so there is no reason to make the physical installer handle SSH keys.

## Mainland-China caveat

The node is initially being configured in mainland China. Tailscale generally tries direct peer-to-peer connectivity and falls back to encrypted relay paths when direct connectivity is unavailable. Cross-border routing and the lack of an official mainland-China relay location can make latency or reliability less predictable than in many other regions.

For interactive shell administration, a relayed connection can still be entirely adequate. Test the connection from the operator's real network before relying on it unattended.

Useful diagnostics:

```bash
tailscale status
tailscale ping redmi-01
```

They show whether the connection is direct or relayed.

## Fallback: reverse SSH

If Tailscale is unavailable or performs poorly and the operator has a public server reachable from both sides, the node can maintain an outbound reverse SSH tunnel to that server. Because the node initiates the connection, this works through ordinary home NAT.

Conceptually:

```bash
ssh -N -R 127.0.0.1:2222:localhost:22 USER@YOUR_SERVER
```

Then, from the server:

```bash
ssh -p 2222 LOCAL_USER@127.0.0.1
```

A real deployment should use SSH keys, host-key checking, a dedicated account and a persistent systemd/autossh service.

## GitHub Actions does not require inbound SSH

A GitHub self-hosted Actions runner establishes outbound connections to GitHub. CI execution does not require a public IP address or inbound SSH.

Remote shell access is for administration; runner connectivity is a separate outbound path.

## After remote access is proven

Make the laptop behave like an unattended node:

- prevent suspend while connected to AC power;
- decide what closing the lid should do;
- configure a 70–80% battery charge ceiling;
- enable automatic security updates;
- prefer wired Ethernet at its long-term location when practical;
- verify remote recovery after a reboot before relying on the machine unattended.

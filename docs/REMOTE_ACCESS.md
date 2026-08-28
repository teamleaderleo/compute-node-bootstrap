# Remote access

The physical install and the remote-access design are separate problems.

The first goal is simple: get Ubuntu online, enable OpenSSH, and prove that SSH works **on the local network**. Then choose a durable remote path based on where the machine actually lives and what connectivity works there.

## 1. Prove SSH on the LAN

On the REDMI Book:

```bash
hostname
hostname -I
systemctl status ssh --no-pager
```

From another computer on the same LAN:

```bash
ssh USER@LAN_IP
```

Once that works, install the operator's SSH public key in `~/.ssh/authorized_keys`. After key login has been proven, password SSH can be disabled.

## 2. Do not forward public port 22

Avoid a router rule that exposes the laptop's SSH daemon directly to the public internet.

A CI node usually has no need for unsolicited public inbound connections.

## 3. Remote-access options

Choose this after testing the final network.

### Private overlay network

Tools such as Tailscale or ZeroTier can make the node reachable through a private address without router port forwarding. They are convenient when their control/data paths work reliably from the node's location.

For a machine initially configured in mainland China, treat this as something to **test**, rather than a prerequisite for completing the Ubuntu install.

### Reverse SSH through a server you control

If you have a small public server reachable from both sides, the node can establish an outbound SSH connection to that server and publish a loopback-only reverse port there. This traverses ordinary home NAT because the connection originates from the node.

Conceptually:

```bash
ssh -N -R 127.0.0.1:2222:localhost:22 USER@YOUR_SERVER
```

Then, on the server:

```bash
ssh -p 2222 LOCAL_USER@127.0.0.1
```

Do the real setup with SSH keys, host-key checking, a dedicated account, and a systemd/autossh service. The exact configuration belongs with the server configuration rather than in the family-facing install instructions.

### GitHub Actions runner

A GitHub self-hosted Actions runner establishes outbound connections to GitHub. CI execution therefore does **not** require inbound SSH or a public IP address.

That makes it useful as an independent management path: the node can be doing CI even while we are still deciding how we want interactive administration to work.

## 4. China → later location

If the node is first configured in China and later moved elsewhere, keep the machine setup location-independent:

- hostname describes the machine, not the city;
- Wi-Fi credentials can change without changing the runner identity;
- remote access is a replaceable layer;
- GitHub/Glaeda configuration should assume ordinary outbound internet, rather than a fixed residential IP.

## 5. After remote access is proven

Then make the laptop behave like a node:

- prevent suspend while connected to AC power;
- decide what closing the lid should do;
- configure a 70–80% battery charge ceiling;
- enable automatic security updates;
- prefer wired Ethernet at its long-term location when practical;
- verify recovery after a reboot before relying on the machine unattended.

Do those changes remotely after the base installation is known-good. They do not need to complicate the first video-call install.

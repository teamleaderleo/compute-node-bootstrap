# Remote access

For the REDMI Book, treat **reachability** and **SSH authentication** as separate layers.

The easiest first foothold is Tailscale because it avoids router port forwarding. After the first remote session, install a normal, explicitly named SSH key as the durable OpenSSH credential.

## 1. Initial foothold with Tailscale

The family-facing install guide contains the exact copy/paste blocks.

On Linux, Tailscale runs as a system service even when nobody is logged in. Installing it with the command-line package does not add a required desktop tray workflow on the REDMI Book.

The first setup can temporarily enable Tailscale SSH:

```bash
sudo tailscale up --ssh --hostname=big-red
```

That prints a `https://login.tailscale.com/...` authentication URL. The person physically holding the node sends that URL to the operator; the operator authenticates the node into the tailnet.

From a device on the same tailnet:

```bash
ssh leo@big-red
```

Once that works, do the rest remotely.

## 2. Add a conventional, explicitly named SSH key

Do **not** rely on the default filename `~/.ssh/id_ed25519`, because it may already exist.

On the operator Mac, create a machine-specific key:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_big_red -C "big-red"
```

This creates:

```text
~/.ssh/id_ed25519_big_red       # private; keep on the operator Mac
~/.ssh/id_ed25519_big_red.pub   # public; install on big-red
```

After the operator already has a shell on the REDMI Book, add the public key to the Ubuntu account's `~/.ssh/authorized_keys`, then verify a new login before disabling any password/Tailscale-SSH fallback.

A convenient Mac SSH config is below. `tailscale nc` deliberately bypasses a competing macOS `100.64.0.0/10` route installed by Stash.

```sshconfig
Host big-red
    HostName big-red
    User leo
    IdentityFile ~/.ssh/id_ed25519_big_red
    IdentitiesOnly yes
    ProxyCommand /usr/local/bin/tailscale nc %h %p
```

Then ordinary use is simply:

```bash
ssh big-red
```

If we want Tailscale only for network reachability and normal OpenSSH for authentication, disable Tailscale SSH after the key login is proven:

```bash
sudo tailscale set --ssh=false
```

Tailscale can remain connected in the background solely to provide the private route to the machine.

## 3. About the Tailscale icon on the operator Mac

The standard macOS Tailscale app normally has a menu-bar icon while it is running. If that UI is annoying, it does not affect the REDMI Book: Linux Tailscale is a background system service.

There is also a CLI-only macOS Tailscale variant, though Tailscale recommends it mainly for experienced administrators. Another option is simply to keep the normal Mac app and connect/disconnect it when remote access is needed.

The GL.iNet router can independently join the tailnet for router-level routing; see [GL.iNet router → REDMI exit node](GLINET_EXIT_NODE.md).

## 4. Why OpenSSH stays installed

Normal OpenSSH gives us a second authentication/recovery path and works on the LAN even when Tailscale is unavailable.

Do not expose public port 22 directly unless there is a deliberate reason and corresponding hardening.

## 5. Mainland-China caveat

The node is initially being configured in mainland China. Tailscale tries direct peer-to-peer connectivity and falls back to encrypted relays when direct connectivity is unavailable. Cross-border routing can make latency/reliability less predictable than elsewhere.

Useful diagnostics:

```bash
tailscale status
tailscale ping big-red
```

Test the real remote path while someone is still physically with the laptop.

## 6. Fallback: reverse SSH

If Tailscale is unavailable or performs poorly and the operator has a public server reachable from both sides, the node can maintain an outbound reverse SSH tunnel to that server.

Conceptually:

```bash
ssh -N -R 127.0.0.1:2222:localhost:22 USER@YOUR_SERVER
```

Then, from the server:

```bash
ssh -p 2222 LOCAL_USER@127.0.0.1
```

A real deployment should use SSH keys, host-key checking, a dedicated account and a persistent service.

## 7. GitHub Actions does not require inbound SSH

A GitHub self-hosted Actions runner establishes outbound connections to GitHub. CI execution does not require a public IP address or inbound SSH.

## 8. Actual `big-red` result

The completed machine uses conventional OpenSSH through Tailscale, has Tailscale SSH disabled, does not suspend automatically while open, suspends when its lid is deliberately closed, disables Wi-Fi power saving and permits passwordless remote administration. See [`BIG_RED_STATE.md`](BIG_RED_STATE.md) for the exact observed state and recovery commands.

No supported battery charge-threshold interface was exposed by this laptop's installed firmware, so no charge ceiling was guessed or forced.

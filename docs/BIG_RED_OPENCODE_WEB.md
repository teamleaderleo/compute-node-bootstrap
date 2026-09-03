# Big Red OpenCode Web over Tailscale

Big Red runs OpenCode Web as the `leo` user from `/home/leo/Projects`. The service listens only on `127.0.0.1:4096`; Tailscale Serve terminates HTTPS and proxies the tailnet-only MagicDNS URL to that loopback backend.

## Install

From the reviewed `compute-node-bootstrap` checkout on Big Red:

```bash
scripts/install-big-red-opencode-web --plan
scripts/install-big-red-opencode-web
scripts/install-big-red-opencode-web --verify-only
```

Tailnet membership is the browser access control. OpenCode does not present a second HTTP Basic Auth prompt, because that prompt is poorly retained by mobile Safari and creates needless repeated-login friction. The backend remains loopback-only, Tailscale Serve remains tailnet-only, and Funnel remains disabled.

The service pins `opencode/muse-spark-1.3-contributor-free` as the Web UI default. The installer verifies both that the exact model remains in OpenCode's catalog and that the running server reports it as the active default.

An older installation may retain `~/.config/big-red-opencode-web/server-password`. The current service does not read it. The installer deliberately leaves that private file untouched instead of printing, moving, or deleting it.

## Persistence and access

`big-red-opencode-web.service` is enabled in the lingering `leo` user manager, so it starts without a graphical login and survives logout and reboot. It requires neither the Linux desktop nor a GPU.

`tailscale serve --bg` persists the HTTPS reverse proxy across tailscaled restarts and reboot. It does not enable Tailscale Funnel and does not open the OpenCode port on LAN or public interfaces.

With Tailscale connected on a phone or tablet, open the HTTPS URL printed by `--plan` or `--verify-only` and choose a repository under `/home/leo/Projects`. No additional browser login is required.

## Verify and operate

```bash
systemctl --user status big-red-opencode-web.service
tailscale serve status
scripts/install-big-red-opencode-web --verify-only
```

The verifier checks the enabled/active service and lingering user manager, exact loopback socket, login-free health API, canonical repository root, tailnet-only Serve mapping, disabled Funnel state, and exact Muse Contributor Free model availability.

To disable the browser route intentionally:

```bash
tailscale serve --https=443 --set-path=/ off
systemctl --user disable --now big-red-opencode-web.service
```

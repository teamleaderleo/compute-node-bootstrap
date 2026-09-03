# Big Red OpenCode Web over Tailscale

Big Red runs OpenCode Web as the `leo` user from `/home/leo/Projects`. The service listens only on `127.0.0.1:4096`; Tailscale Serve terminates HTTPS and proxies the tailnet-only MagicDNS URL to that loopback backend.

## Install

From the reviewed `compute-node-bootstrap` checkout on Big Red:

```bash
scripts/install-big-red-opencode-web --plan
scripts/install-big-red-opencode-web
scripts/install-big-red-opencode-web --verify-only
```

The installer creates a random OpenCode server password once at `~/.config/big-red-opencode-web/server-password`, with directory mode `0700` and file mode `0600`. The systemd user unit receives it through `LoadCredential` and exports it only to OpenCode as the supported `OPENCODE_SERVER_PASSWORD` value. The password is never printed by the installer.

The username remains OpenCode's default, `opencode`. Retrieve the password only in an attended private Big Red terminal when adding it to a client password manager; do not put it in shell history, GitHub, or workspace prose.

## Persistence and access

`big-red-opencode-web.service` is enabled in the lingering `leo` user manager, so it starts without a graphical login and survives logout and reboot. It requires neither the Linux desktop nor a GPU.

`tailscale serve --bg` persists the HTTPS reverse proxy across tailscaled restarts and reboot. It does not enable Tailscale Funnel and does not open the OpenCode port on LAN or public interfaces.

With Tailscale connected on a phone or tablet, open the HTTPS URL printed by `--plan` or `--verify-only`, authenticate as `opencode`, and choose a repository under `/home/leo/Projects`.

## Verify and operate

```bash
systemctl --user status big-red-opencode-web.service
tailscale serve status
scripts/install-big-red-opencode-web --verify-only
```

The verifier checks the private credential shape, enabled/active service and lingering user manager, exact loopback socket, password-protected health API, canonical repository root, tailnet-only Serve mapping, disabled Funnel state, and exact Muse Contributor Free model availability.

To disable the browser route intentionally:

```bash
tailscale serve --https=443 off
systemctl --user disable --now big-red-opencode-web.service
```

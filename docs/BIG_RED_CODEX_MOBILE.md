# Big Red Codex from a phone or tablet

Big Red exposes a tailnet-only browser terminal that launches the real Codex
harness. It is separate from OpenCode Web: the page starts or reattaches Codex
CLI sessions with one of three explicit choices:

- Muse Spark 1.3 Contributor Free at X High (`muse-xhigh`);
- Muse Spark 1.3 Contributor Free at High (`muse-high`);
- the existing unprofiled Sol default.

The terminal asks for one top-level Git repository under `/home/leo/Projects`
and keeps each model/repository combination in a named `tmux` session. Closing
the browser or losing mobile connectivity detaches the client without stopping
Codex. Reopening the same choice reattaches the session.

## Install

From the reviewed `compute-node-bootstrap` checkout on Big Red:

```bash
scripts/install-big-red-codex-mobile --plan
scripts/install-big-red-codex-mobile
scripts/install-big-red-codex-mobile --verify-only
```

The installer adds Ubuntu's `ttyd` package when absent, installs the reviewed
launcher and user systemd unit, enables user lingering, and creates a persistent
Tailscale Serve HTTPS mapping on port 8444. The terminal backend listens only
on `127.0.0.1:7681`; no LAN or public listener and no Funnel route are created.
Tailnet membership is the access boundary, matching the existing private
Tailscale administration path. The endpoint does not ask for a second password.

The service is headless and GPU-independent. It uses the same local Codex
profiles and OpenCode Zen credential helper already installed for the normal
Big Red CLI.

## Use

Connect the phone or tablet to the tailnet, open the HTTPS URL printed by the
installer, choose the model, and type a repository name such as `glaeda` or
`leo-workspace`. Use `muse-xhigh` for the longest or most demanding work.

The page has the authority of the `leo` account. Do not expose it through
Tailscale Funnel, a router port forward, or a public reverse proxy.

## Verify and disable

```bash
systemctl --user status big-red-codex-mobile.service
tailscale serve status
scripts/install-big-red-codex-mobile --verify-only
```

To remove only this browser route without disturbing OpenCode Web on HTTPS 443:

```bash
tailscale serve --https=8444 off
systemctl --user disable --now big-red-codex-mobile.service
```

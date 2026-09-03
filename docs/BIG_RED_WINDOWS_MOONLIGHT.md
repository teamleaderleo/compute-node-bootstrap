# Big Red Windows through Sunshine and Moonlight

This is the private low-friction desktop path for Big Red's GPU-passthrough Windows VM:

```text
Air Blue Moonlight -> Tailscale -> big-red -> restricted host forwarding -> Sunshine -> Windows Desktop
```

It does not expose Sunshine to the public internet. The Ubuntu host forwards only Sunshine's pairing, control, audio and video ports arriving on `tailscale0`; the Web UI port is excluded. There is no router port-forward or LAN listener. The stable client target is Big Red's MagicDNS name, `big-red.<tailnet>.ts.net`.

This route complements, rather than replaces, the Ubuntu host's SSH, Codex Remote, and GNOME Remote Desktop paths. Sunshine runs inside the Windows guest and does not depend on an Ubuntu graphical session. The guest owns the passthrough GPU while it is running.

## Applied state

- Windows VM: `win11-starsector`
- Sunshine: `2026.516.143833`
- Tailscale for Windows: `1.102.3`, unattended mode, hostname `big-red-windows`
- Moonlight on Air Blue: `6.1.0`
- Sunshine computer name: **Big Red Windows**
- Moonlight Desktop profile: 1280x800, 30 FPS, 4 Mbps, H.264, remote-desktop mouse mode
- Moonlight Direct Launch: enabled for Desktop
- Windows services: `SunshineService` and `Tailscale`, both Automatic
- Ubuntu service: `big-red-windows-moonlight-forward.service`, enabled and active
- Tailnet-only forwarding: TCP 47984, 47989 and 48010; UDP 47998-48000
- Sunshine Web UI 47990: not forwarded by the Ubuntu route

The Sunshine Web UI has a generated password. The credential is not in this repository, command output, or machine-state prose. Keep it in the operator's private password manager or OS credential store. Moonlight's client certificate and pairing key likewise remain in its application data.

## Windows guest installation

Download the official 64-bit Windows installers from the Sunshine GitHub releases and Tailscale's stable package repository. Verify both Authenticode signatures before installation. The currently deployed Sunshine MSI had SHA-256:

```text
e7208b11a4ab9dd89871133a054bbb8dc55dfbba408227b0eccab22c60b273a2
```

Install both packages for all users. Configure Tailscale through its supported sign-in flow, then make it independent of an interactive Windows login:

```powershell
& "$env:ProgramFiles\Tailscale\tailscale.exe" set --hostname=big-red-windows --unattended
Set-Service Tailscale -StartupType Automatic
Set-Service SunshineService -StartupType Automatic
```

Set Sunshine's Web UI credentials using its supported credential command or Web UI. Do not put the password on a committed command line. In Sunshine Configuration, set:

```text
sunshine_name = Big Red Windows
udp_batch_send = 0
external_ip = <Big Red Tailscale IPv4>
```

`udp_batch_send = 0` avoids the observed Windows `WSASendMsg` failure on this route. Leave the built-in **Desktop** application enabled. Pair each Moonlight client through Sunshine's PIN page.

## Air Blue client

Install Moonlight and add the Windows guest by MagicDNS name:

```bash
brew install --cask moonlight
/Applications/Moonlight.app/Contents/MacOS/Moonlight add \
  big-red.<tailnet>.ts.net
```

Do not use Homebrew's symlinked Moonlight executable if Qt reports missing platform plugins; launch the executable inside the application bundle as shown above.

The tested global stream settings can be applied while Moonlight is closed:

```bash
defaults write com.moonlight-stream.Moonlight width -int 1280
defaults write com.moonlight-stream.Moonlight height -int 800
defaults write com.moonlight-stream.Moonlight fps -int 30
defaults write com.moonlight-stream.Moonlight bitrate -int 4000
defaults write com.moonlight-stream.Moonlight videocfg -int 1
defaults write com.moonlight-stream.Moonlight mouseacceleration -bool true
defaults write com.moonlight-stream.Moonlight keepawake -bool true
```

In Moonlight, enable **Direct Launch** for the Desktop app. Selecting the **Big Red Windows** computer tile then opens the Windows desktop without an intermediate application grid.

## Verification

In an elevated Windows PowerShell:

```powershell
Get-Service SunshineService,Tailscale |
  Select-Object Name,Status,StartType
& "$env:ProgramFiles\Tailscale\tailscale.exe" status
```

On Air Blue:

```bash
tailscale ping big-red.<tailnet>.ts.net
/Applications/Moonlight.app/Contents/MacOS/Moonlight list \
  big-red.<tailnet>.ts.net
```

The Moonlight list must include `Desktop`. Launch the **Big Red Windows** tile and confirm the Windows desktop renders and accepts keyboard and mouse input. Restart both Windows services and repeat the checks to verify persistence.

The Windows guest's own Tailscale node may still use DERP because it sits behind libvirt and the upstream NAT. Normal Air Blue use targets the Ubuntu host instead, reusing its direct Tailscale UDP path. The checked-in installer owns the narrow nftables forwarding table and the guest's fixed libvirt DHCP reservation:

```bash
scripts/install-big-red-windows-moonlight-forward --plan
scripts/install-big-red-windows-moonlight-forward
scripts/install-big-red-windows-moonlight-forward --verify-only
```

Sunshine advertises Big Red's Tailscale IPv4 as `external_ip`, so Moonlight keeps the host route for the RTSP session. This value is not a public address and does not create a listener by itself.

## Recovery

If the tile is offline, check in order:

1. `virsh domstate win11-starsector` on the Ubuntu host;
2. the Windows `Tailscale` service;
3. the Windows `SunshineService` service;
4. `tailscale ping` and Moonlight `list` from Air Blue;
5. Sunshine logs for encoder or socket errors.

The VM is intentionally not documented here as an always-on Ubuntu boot dependency. Starting or stopping it changes ownership of the passthrough GPU and should remain an explicit workstation-mode decision.

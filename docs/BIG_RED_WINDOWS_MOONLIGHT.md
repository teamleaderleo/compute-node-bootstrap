# Big Red Windows through Sunshine and Moonlight

This is the private low-friction desktop path for Big Red's GPU-passthrough Windows VM:

```text
Air Blue Moonlight -> Tailscale -> big-red-windows -> Sunshine -> Windows Desktop
```

It does not expose Sunshine to the public internet. The Windows guest has only its libvirt NAT interface and its tailnet interface; there is no router port-forward. The stable client target is the guest's MagicDNS name, `big-red-windows.<tailnet>.ts.net`, rather than an address from the libvirt network.

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
```

`udp_batch_send = 0` avoids the observed Windows `WSASendMsg` failure on this route. Leave the built-in **Desktop** application enabled. Pair each Moonlight client through Sunshine's PIN page.

## Air Blue client

Install Moonlight and add the Windows guest by MagicDNS name:

```bash
brew install --cask moonlight
/Applications/Moonlight.app/Contents/MacOS/Moonlight add \
  big-red-windows.<tailnet>.ts.net
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
tailscale ping big-red-windows.<tailnet>.ts.net
/Applications/Moonlight.app/Contents/MacOS/Moonlight list \
  big-red-windows.<tailnet>.ts.net
```

The Moonlight list must include `Desktop`. Launch the **Big Red Windows** tile and confirm the Windows desktop renders and accepts keyboard and mouse input. Restart both Windows services and repeat the checks to verify persistence.

The observed remote path currently relays through a Tailscale DERP region instead of establishing a direct UDP path. The tested profile remains usable and hardware encoding/decoding keeps endpoint processing low, but interaction latency follows the relay path. Re-run `tailscale ping` after either side's network changes; a direct result materially improves responsiveness without changing Moonlight or Sunshine.

## Recovery

If the tile is offline, check in order:

1. `virsh domstate win11-starsector` on the Ubuntu host;
2. the Windows `Tailscale` service;
3. the Windows `SunshineService` service;
4. `tailscale ping` and Moonlight `list` from Air Blue;
5. Sunshine logs for encoder or socket errors.

The VM is intentionally not documented here as an always-on Ubuntu boot dependency. Starting or stopping it changes ownership of the passthrough GPU and should remain an explicit workstation-mode decision.

# `big-red` workstation applications and file handlers

Big Red keeps one small Ubuntu-archive application set for common local files instead of sending
documents to a browser or adding several overlapping tools. Project-specific runtimes remain owned
by their repositories.

Apply the reviewed set for the existing operator account:

```bash
cd /home/leo/Projects/compute-node-bootstrap
./scripts/configure-big-red-workstation.sh --plan
./scripts/configure-big-red-workstation.sh --operator-user leo
./scripts/configure-big-red-workstation.sh --verify-only --operator-user leo
```

The script installs:

- system `ripgrep`, `sqlite3` and `hyperfine` for dependable SSH inspection and bounded benchmarks;
- `just`, `fzf`, `fd`, `bat`, `zoxide`, `btop` and `git-delta` for task running, search,
  navigation, readable inspection and process visibility;
- JetBrains Mono, GNOME Screenshot, Tweaks and Extension Manager for a legible desktop and
  operator-controlled visual experiments;
- LibreOffice Writer, Calc, Impress and its GTK integration, without the broad office meta-package;
- GNOME Showtime, Amberol and File Roller for video, audio and archives;
- Remmina with the Ubuntu dependency-selected RDP/VNC plugins.

It then assigns Writer/Calc/Impress to Office and OpenDocument formats, Showtime to common video,
Amberol to common audio, File Roller to common archives and Remmina to RDP links. Papers remains the
PDF handler and Loupe remains the image handler. The settings are per-user; a later Mom or Sister
account receives independent defaults.

Ubuntu packages the `fd` and `bat` binaries as `fdfind` and `batcat`. The script writes a small
managed fragment at `~/.config/big-red/devx.bash`, sources it from `.bash_aliases`, and provides the
ordinary names. Interactive shells also receive zoxide plus fzf completion and history/key
bindings. It sets GNOME's monospace font to JetBrains Mono 11. It installs no input-injection or
clipboard-history daemon and enables no shell extension.

On 2026-08-29, the initial Big Red application added 86 archive packages, downloaded 120 MB and
used 418 MB of disk. It removed and upgraded nothing. Exact package counts can change with Ubuntu
updates, so always inspect `--plan` plus an APT simulation before a rebuild if the delta matters.
The 2026-08-31 DevX addition installed 13 packages including two dependencies, downloaded 12.1 MB,
used 39.5 MB, and likewise upgraded and removed nothing.

The same live acceptance found no package-owned XDG autostart or systemd unit, no resident
LibreOffice/Showtime/Amberol/File Roller/Remmina process, no new development listener and no failed
system or user unit. Showtime, Amberol and File Roller install D-Bus activation files, which start
the requested app on demand rather than keeping it resident. Writer, Calc and Impress each returned
LibreOffice 26.2.5.2 successfully in headless mode. SSH, Tailscale and NetworkManager remained
active; screen blanking, lid suspend and the hibernate masks were unchanged.

## Verification boundary

`--verify-only` checks every explicitly requested package, desktop entry and MIME mapping without
opening a GUI or changing state. It does not claim that every possible codec or malformed document
works. Use a disposable known-good file for an owner-present GUI acceptance test when that format is
actually needed.

After installation, also check failed units, new autostarts and listeners. None of these applications
should become a resident service merely because its package is installed. Remmina stores connection
profiles separately; installing it does not authorize creating or saving a remote connection.

## Rollback

First use the desktop's **Open With** action or `xdg-mime default DESKTOP MIME` to select the desired
replacement handlers. Then remove only the explicitly requested top-level packages:

```bash
sudo apt remove \
  ripgrep sqlite3 hyperfine just fzf fd-find bat zoxide btop git-delta \
  fonts-jetbrains-mono gnome-screenshot gnome-shell-extension-manager gnome-tweaks \
  libreoffice-writer libreoffice-calc libreoffice-impress libreoffice-gtk3 \
  showtime amberol file-roller remmina
sudo apt autoremove --dry-run
```

Review the dry-run before removing dependencies. Do not run an unattended `autoremove`: another
application may now use a library that originally arrived with this batch. Papers and Loupe are
part of the existing GNOME baseline and are not rollback targets.

Before package removal, restore the previous font and remove the managed fragment after reviewing
it:

```bash
gsettings set org.gnome.desktop.interface monospace-font-name 'Ubuntu Sans Mono 11'
rm ~/.config/big-red/devx.bash
```

The guarded source line in `.bash_aliases` becomes a no-op when the fragment is absent and may stay.
Remove that exact line manually if desired; do not delete `.bash_aliases`, which may contain
unrelated user configuration.

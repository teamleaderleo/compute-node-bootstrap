#!/usr/bin/env bash
set -euo pipefail

mode=apply
operator_user=${SUDO_USER:-leo}

usage() {
  cat <<'EOF'
Usage: configure-big-red-workstation.sh [--plan|--verify-only] [--operator-user USER]

Install Big Red's small Ubuntu-native workstation application set and assign
reviewed per-user file handlers. --plan and --verify-only never mutate state.
EOF
}

while (($#)); do
  case "$1" in
    --plan)
      mode=plan
      shift
      ;;
    --verify-only)
      mode=verify
      shift
      ;;
    --operator-user)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      operator_user=$2
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

operator_home=$(getent passwd "$operator_user" | cut -d: -f6 || true)
[[ -n "$operator_home" && -d "$operator_home" ]] || {
  printf 'error: operator user %s has no existing home directory\n' "$operator_user" >&2
  exit 1
}

packages=(
  ripgrep
  sqlite3
  hyperfine
  just
  fzf
  fd-find
  bat
  zoxide
  btop
  git-delta
  fonts-jetbrains-mono
  gnome-screenshot
  gnome-shell-extension-manager
  gnome-tweaks
  libreoffice-writer
  libreoffice-calc
  libreoffice-impress
  libreoffice-gtk3
  showtime
  amberol
  file-roller
  remmina
  xdg-utils
)

devx_fragment_relative=.config/big-red/devx.bash
devx_fragment="$operator_home/$devx_fragment_relative"
aliases_file="$operator_home/.bash_aliases"
# The generated shell must expand its own HOME, not the provisioning shell's.
# shellcheck disable=SC2016
devx_source_line='[ -r "$HOME/.config/big-red/devx.bash" ] && . "$HOME/.config/big-red/devx.bash"'
monospace_font='JetBrains Mono 11'

# One reviewed desktop application per ordinary local file-handling job.
associations=(
  'libreoffice-writer.desktop|application/vnd.openxmlformats-officedocument.wordprocessingml.document'
  'libreoffice-writer.desktop|application/msword'
  'libreoffice-writer.desktop|application/vnd.oasis.opendocument.text'
  'libreoffice-calc.desktop|application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  'libreoffice-calc.desktop|application/vnd.ms-excel'
  'libreoffice-calc.desktop|application/vnd.oasis.opendocument.spreadsheet'
  'libreoffice-impress.desktop|application/vnd.openxmlformats-officedocument.presentationml.presentation'
  'libreoffice-impress.desktop|application/vnd.ms-powerpoint'
  'libreoffice-impress.desktop|application/vnd.oasis.opendocument.presentation'
  'org.gnome.Showtime.desktop|video/mp4'
  'org.gnome.Showtime.desktop|video/x-matroska'
  'org.gnome.Showtime.desktop|video/webm'
  'io.bassi.Amberol.desktop|audio/mpeg'
  'io.bassi.Amberol.desktop|audio/flac'
  'io.bassi.Amberol.desktop|audio/ogg'
  'io.bassi.Amberol.desktop|audio/x-vorbis+ogg'
  'org.gnome.FileRoller.desktop|application/zip'
  'org.gnome.FileRoller.desktop|application/x-7z-compressed'
  'org.gnome.FileRoller.desktop|application/x-tar'
  'org.gnome.FileRoller.desktop|application/gzip'
  'org.remmina.Remmina-file.desktop|x-scheme-handler/rdp'
  'org.gnome.Papers.desktop|application/pdf'
  'org.gnome.Loupe.desktop|image/png'
  'org.gnome.Loupe.desktop|image/jpeg'
  'org.gnome.Loupe.desktop|image/webp'
)

as_operator() {
  sudo -u "$operator_user" env \
    HOME="$operator_home" \
    XDG_CONFIG_HOME="$operator_home/.config" \
    "$@"
}

devx_fragment_content() {
  cat <<'EOF'
# Managed by compute-node-bootstrap.
alias fd='fdfind'
alias bat='batcat'

if [[ $- == *i* ]]; then
    eval "$(zoxide init bash)"
    [ -r /usr/share/doc/fzf/examples/completion.bash ] && . /usr/share/doc/fzf/examples/completion.bash
    [ -r /usr/share/doc/fzf/examples/key-bindings.bash ] && . /usr/share/doc/fzf/examples/key-bindings.bash
fi
EOF
}

install_devx_config() {
  local operator_group temporary
  if [[ -L "$aliases_file" ]]; then
    printf 'error: refusing symlinked .bash_aliases\n' >&2
    return 1
  fi
  operator_group=$(id -gn "$operator_user")
  temporary=$(mktemp)
  trap 'rm -f "$temporary"' RETURN
  devx_fragment_content >"$temporary"
  sudo install -d -o "$operator_user" -g "$operator_group" -m 0755 "$(dirname "$devx_fragment")"
  sudo install -o "$operator_user" -g "$operator_group" -m 0644 "$temporary" "$devx_fragment"
  as_operator touch "$aliases_file"
  if ! grep -Fqx "$devx_source_line" "$aliases_file"; then
    printf '\n%s\n' "$devx_source_line" | sudo -u "$operator_user" tee -a "$aliases_file" >/dev/null
  fi
  # A remote sudo invocation may not inherit the graphical session bus. Use a
  # private bus so dconf commits instead of warning and returning false success.
  as_operator dbus-run-session -- \
    gsettings set org.gnome.desktop.interface monospace-font-name "$monospace_font"
}

print_plan() {
  printf 'operator_user=%s\n' "$operator_user"
  printf 'packages:'
  printf ' %s' "${packages[@]}"
  printf '\nassociations:\n'
  printf '  %s\n' "${associations[@]}"
  printf 'shell_fragment=%s\n' "$devx_fragment_relative"
  printf 'monospace_font=%s\n' "$monospace_font"
}

verify() {
  local failed=0 entry desktop mime actual expected_fragment
  for package in "${packages[@]}"; do
    if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -qx 'install ok installed'; then
      printf 'missing package: %s\n' "$package" >&2
      failed=1
    fi
  done

  expected_fragment=$(devx_fragment_content)
  if [[ ! -f "$devx_fragment" ]] || [[ $(<"$devx_fragment") != "$expected_fragment" ]]; then
    printf 'managed shell fragment mismatch: %s\n' "$devx_fragment_relative" >&2
    failed=1
  fi
  if [[ ! -f "$aliases_file" ]] || ! grep -Fqx "$devx_source_line" "$aliases_file"; then
    printf 'missing shell fragment source in .bash_aliases\n' >&2
    failed=1
  fi
  actual=$(as_operator gsettings get org.gnome.desktop.interface monospace-font-name || true)
  if [[ "$actual" != "'$monospace_font'" ]]; then
    printf 'monospace font mismatch: expected=%s actual=%s\n' \
      "$monospace_font" "${actual:-unset}" >&2
    failed=1
  fi

  for entry in "${associations[@]}"; do
    IFS='|' read -r desktop mime <<<"$entry"
    if [[ ! -f "/usr/share/applications/$desktop" ]]; then
      printf 'missing desktop entry: %s\n' "$desktop" >&2
      failed=1
      continue
    fi
    actual=$(as_operator xdg-mime query default "$mime" || true)
    if [[ "$actual" != "$desktop" ]]; then
      printf 'association mismatch: %s expected=%s actual=%s\n' \
        "$mime" "$desktop" "${actual:-unset}" >&2
      failed=1
    fi
  done
  return "$failed"
}

case "$mode" in
  plan)
    print_plan
    ;;
  verify)
    verify
    printf 'Big Red workstation file loop verified.\n'
    ;;
  apply)
    print_plan
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
    install_devx_config
    for entry in "${associations[@]}"; do
      IFS='|' read -r desktop mime <<<"$entry"
      as_operator xdg-mime default "$desktop" "$mime"
    done
    verify
    printf 'Big Red workstation file loop configured and verified.\n'
    ;;
esac

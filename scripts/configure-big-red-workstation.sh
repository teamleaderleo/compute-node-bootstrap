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

print_plan() {
  printf 'operator_user=%s\n' "$operator_user"
  printf 'packages:'
  printf ' %s' "${packages[@]}"
  printf '\nassociations:\n'
  printf '  %s\n' "${associations[@]}"
}

verify() {
  local failed=0 entry desktop mime actual
  for package in "${packages[@]}"; do
    if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -qx 'install ok installed'; then
      printf 'missing package: %s\n' "$package" >&2
      failed=1
    fi
  done

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
    for entry in "${associations[@]}"; do
      IFS='|' read -r desktop mime <<<"$entry"
      as_operator xdg-mime default "$desktop" "$mime"
    done
    verify
    printf 'Big Red workstation file loop configured and verified.\n'
    ;;
esac

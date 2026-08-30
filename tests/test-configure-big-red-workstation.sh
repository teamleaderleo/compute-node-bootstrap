#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/scripts/configure-big-red-workstation.sh"
operator_user=$(id -un)

bash -n "$script"
plan=$($script --plan --operator-user "$operator_user")

for expected in \
  'just' 'fzf' 'fd-find' 'bat' 'zoxide' 'btop' 'git-delta' \
  'fonts-jetbrains-mono' 'gnome-screenshot' 'gnome-shell-extension-manager' 'gnome-tweaks'; do
  grep -Eq "packages:.*(^| )${expected}( |$)" <<<"$plan"
done

grep -Fxq 'shell_fragment=.config/big-red/devx.bash' <<<"$plan"
grep -Fxq 'monospace_font=JetBrains Mono 11' <<<"$plan"

printf 'configure-big-red-workstation plan verified.\n'

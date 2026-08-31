#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/scripts/install-big-red-jj"
operator_user=$(id -un)

bash -n "$script"
plan=$(bash "$script" --plan --operator-user "$operator_user")

grep -Fxq 'jj_version=0.44.0' <<<"$plan"
grep -Fxq 'asset=jj-v0.44.0-x86_64-unknown-linux-musl.tar.gz' <<<"$plan"
grep -Fxq 'asset_sha256=0a07bab4641a55fd2bc2fd1563ba3a3f9a577584086ad74086a1c5b69b3ffce9' <<<"$plan"
grep -Fxq 'install_relative=.local/lib/big-red-tools/jj/v0.44.0/jj' <<<"$plan"
grep -Fxq 'launcher_relative=.local/bin/jj' <<<"$plan"

grep -Fq 'https://github.com/jj-vcs/jj/releases/download/v${version}/${asset}' "$script"
grep -Fq "minimum_git_version=2.41.0" "$script"
grep -Fq 'observed_archive_sha=$(as_operator sha256sum "$archive"' "$script"
grep -Fq '[[ "$observed_archive_sha" == "$archive_sha256" ]]' "$script"
grep -Fq "refusing to replace existing launcher" "$script"
grep -Fq "refusing jj install root with unexpected contents" "$script"

printf 'install-big-red-jj plan verified.\n'

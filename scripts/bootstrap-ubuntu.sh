#!/usr/bin/env bash
set -euo pipefail

printf '== compute-node-bootstrap: Ubuntu baseline ==\n'

sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt full-upgrade -y
sudo apt install -y \
  openssh-server \
  git \
  curl \
  ca-certificates \
  build-essential \
  jq \
  tmux \
  htop \
  nvme-cli \
  pciutils \
  usbutils \
  unzip \
  zip

sudo systemctl enable --now ssh

printf '\n== SSH ==\n'
systemctl is-enabled ssh || true
systemctl is-active ssh || true

printf '\n== hostname ==\n'
hostname

printf '\n== LAN addresses ==\n'
hostname -I || true

printf '\nBaseline complete. Do not expose TCP/22 directly to the public internet.\n'

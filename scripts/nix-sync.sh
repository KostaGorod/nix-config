#!/usr/bin/env bash
set -euo pipefail

cd "${HOME}/nix-config"
git fetch origin main
git checkout main
git pull origin main
sudo nixos-rebuild switch --flake ".#$(hostname)" 2>&1 | nom

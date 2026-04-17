# nix-config

Fully declarative NixOS configuration for my daily-driver ThinkPad (`rocinante`).

Plasma 6 and COSMIC side by side, hardware-backed SSH (TPM + YubiKey + fingerprint),
Tailscale mesh, agenix-managed secrets, and a growing set of AI coding tools
(Claude Code, OpenCode, Gemini CLI, Kimi, Droids, Abacus.AI DeepAgent) on top of a
self-hosted Mem0 memory layer backed by Qdrant. Power management is tuned per-profile
with TLP, battery-health thresholds, and runtime PM tweaks.

User environment is managed with home-manager: editors (Helix, VSCode, Zed), shell
(Bash + Starship + Direnv), and the usual desktop apps. Custom overlays patch Spotify
with SpotX and add sensitive-clipboard support to wl-clipboard for password managers.

## Deploy

```sh
sudo nixos-rebuild switch --flake .#rocinante
```

See [`hosts/rocinante/README.md`](hosts/rocinante/README.md) for hardware
details and first-time bootstrap, [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
for the design, and [`docs/SECRETS.md`](docs/SECRETS.md) for the agenix
workflow.

## Layout

| Path           | Purpose                                                  |
|----------------|----------------------------------------------------------|
| `flake.nix`    | Inputs, `nixosConfigurations.rocinante`, `treefmt`       |
| `hosts/`       | Per-host entry points, hardware config, disko layout     |
| `profiles/`    | Role profiles (`workstation.nix`)                        |
| `modules/`     | Reusable NixOS modules (mem0, tailscale, ssh-tpm, …)     |
| `de/`          | Desktop environments (`plasma6.nix`, `cosmic.nix`)       |
| `users/kosta/` | Home-manager config and user packages                    |
| `overlays/`    | Custom package overlays (Spotify SpotX, wl-clipboard)    |
| `packages/`    | Locally built packages                                   |
| `secrets/`     | Age-encrypted secrets (see `docs/SECRETS.md`)            |
| `flakes/`      | Standalone dev shells; see `flakes/README.md`            |
| `docs/`        | Architecture notes and setup guides                      |

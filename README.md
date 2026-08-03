# nix-config

Fully declarative NixOS configuration for my daily-driver ThinkPad (`rocinante`).

Plasma 6 and COSMIC side by side, hardware-backed SSH (TPM + YubiKey + fingerprint),
Tailscale mesh, agenix-managed secrets, and a growing set of AI coding tools
(Claude Code, OpenCode, and Droids). An on-demand Mem0 MCP wrapper is installed;
the persistent Mem0 service and standalone Qdrant container are currently disabled.
Power management is tuned per-profile with TLP, battery-health thresholds, and
runtime PM tweaks.

Editors (Helix, VSCode, Zed), shell tools (Bash + Starship + Direnv), and desktop apps
are managed by NixOS. Kosta's application packages and Git configuration are scoped
to that user; program defaults that use NixOS's global `programs.*` options remain
system-wide. Spotify is patched with SpotX, and wl-clipboard includes
sensitive-clipboard support for password managers.

## Deploy

```sh
sudo nixos-rebuild switch --flake .#rocinante
```

See [`hosts/rocinante/README.md`](hosts/rocinante/README.md) for hardware
details and first-time bootstrap, [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
for the design, and [`docs/SECRETS.md`](docs/SECRETS.md) for the agenix
workflow.

## Layout

| Path           | Purpose                                                     |
|----------------|-------------------------------------------------------------|
| `flake.nix`    | Inputs and the minimal dendritic `import-tree` entry point   |
| `aspects/`     | Auto-imported flake-parts modules and host composition       |
| `hosts/`       | Per-host settings, hardware config, and disko layout         |
| `profiles/`    | Lower-level role profiles (`workstation.nix`)                |
| `modules/`     | Reusable NixOS modules (mem0, tailscale, ssh-tpm, ...)        |
| `de/`          | Desktop environments (`plasma6.nix`, `cosmic.nix`)           |
| `users/kosta/` | NixOS user settings, packages, and selected program defaults |
| `overlays/`    | Package overlays retained for reuse                          |
| `packages/`    | Locally built packages                                       |
| `secrets/`     | Age-encrypted secrets (see `docs/SECRETS.md`)                |
| `flakes/`      | Standalone dev shells; see `flakes/README.md`                |
| `docs/`        | Architecture notes and setup guides                          |

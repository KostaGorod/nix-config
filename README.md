# nix-config

Fully declarative NixOS configuration for my daily-driver ThinkPad (`rocinante`).

Plasma 6 and COSMIC side by side, hardware-backed SSH (TPM + YubiKey + fingerprint),
Tailscale mesh, agenix-managed secrets, and a growing set of AI coding tools
(Claude Code, OpenCode, and Droids). Mem0 and the standalone Qdrant container
are available as optional modules but currently disabled.
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

See [`modules/hosts/rocinante/README.md`](modules/hosts/rocinante/README.md) for hardware
details and first-time bootstrap, [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
for the design, and [`docs/SECRETS.md`](docs/SECRETS.md) for the agenix
workflow.

## Layout

| Path                 | Purpose                                                        |
|----------------------|----------------------------------------------------------------|
| `flake.nix`          | Inputs and the minimal dendritic `import-tree` entry point      |
| `modules/framework/` | Typed deferred-module framework, checks, and formatting         |
| `modules/hosts/`     | Host composition and machine-specific contributions            |
| `modules/users/`     | User-scoped packages and Git configuration                      |
| `modules/{concern}/` | Auto-imported feature contributions grouped by concern          |
| `overlays/`          | Package overlays retained for reuse, outside the import tree    |
| `packages/`          | Locally built package functions, outside the import tree        |
| `secrets/`           | Age-encrypted secrets (see `docs/SECRETS.md`)                   |
| `flakes/`            | Standalone dev shells; see `flakes/README.md`                   |
| `docs/`              | Architecture notes and setup guides                             |

Every non-underscore Nix file under `modules/` is a flake-parts top-level
module. Features merge into `nixos.modules.workstation`, user fragments merge
into `nixos.modules.kosta`, and host policy merges into the rocinante deferred
module. There is no central feature import list.

Top-level features capture the specific flake inputs they need lexically;
inputs are not passed wholesale into the NixOS module evaluation.

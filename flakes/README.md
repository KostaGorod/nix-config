# flakes/

Standalone packaging flakes for tools not in nixpkgs. Each subdirectory is an
independent flake with its own `flake.nix` and `flake.lock`, pinned to
`nixos-unstable` so it can be updated without touching the main flake.

| Flake              | Tool                                       |
|--------------------|--------------------------------------------|
| `abacusai-fhs/`    | Abacus.AI DeepAgent desktop app + CLI      |
| `antigravity-fhs/` | Google Antigravity agentic IDE             |
| `claude-code/`     | Anthropic Claude Code CLI (npm-packaged)   |
| `droids/`          | FactoryAI Droids CLI                       |
| `vibe-kanban/`     | Vibe Kanban agent orchestration tool       |

## Running

```sh
nix run ./flakes/droids
nix run ./flakes/abacusai-fhs#cli
```

The main flake consumes `antigravity` via its upstream input; the rest are
either run ad-hoc or referenced from the relevant module under
`modules/nixos/` (e.g. `abacusai.nix`, `droids.nix`).

## Updating

```sh
nix flake update ./flakes/claude-code
```

`-fhs` suffixed flakes wrap the upstream binary in a FHS-compatible env so
Electron and other glibc-linked blobs run on NixOS without patchelf.

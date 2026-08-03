# flakes/

Standalone packaging flakes for tools not in nixpkgs. Each subdirectory is an
independent flake with its own `flake.nix` and `flake.lock`, pinned to
`nixos-unstable` so it can be updated without touching the main flake.

| Flake              | Tool                                       |
|--------------------|--------------------------------------------|
| `antigravity-fhs/` | Google Antigravity agentic IDE             |
| `claude-code/`     | Anthropic Claude Code CLI (npm-packaged)   |
| `droids/`          | FactoryAI Droids CLI                       |
| `vibe-kanban/`     | Vibe Kanban agent orchestration tool       |

## Running

```sh
nix run ./flakes/droids
```

The main flake consumes Antigravity and the AI CLIs through upstream inputs.
These standalone flakes are retained for ad-hoc packaging and testing; active
system integration lives in the feature tree under `modules/`.

## Updating

```sh
nix flake update ./flakes/claude-code
```

`-fhs` suffixed flakes wrap the upstream binary in a FHS-compatible env so
Electron and other glibc-linked blobs run on NixOS without patchelf.

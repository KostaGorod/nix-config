# AbacusAI DeepAgent Flake

This is a local flake for [AbacusAI DeepAgent](https://abacus.ai/) - an AI-powered development environment with both desktop GUI and CLI tools.

## What is this?

This flake packages the AbacusAI DeepAgent desktop client and CLI directly from GitHub releases using FHS environments for binary compatibility on NixOS.

## Packages

- **gui** / **default**: The AbacusAI desktop application
- **cli**: The standalone CLI agent

## Usage

The packages are already integrated into the rocinante profile in the main nix-config.

To run AbacusAI directly:
```bash
# GUI (default)
nix run /home/kosta/nix-config/flakes/abacusai-fhs

# CLI
nix run /home/kosta/nix-config/flakes/abacusai-fhs#cli
```

## Updating AbacusAI

To update to a new version:

1. Check latest release at https://github.com/abacusai/deepagent-releases/releases
2. Update the `version` variable in `flake.nix`
3. Update the sha256 hashes for both `guiSrc` and `cliSrc`

```bash
# Get new hashes (after updating version in flake.nix)
nix-prefetch-url https://github.com/abacusai/deepagent-releases/releases/download/VERSION/AbacusAI-linux-x64-VERSION.tar.gz
nix-prefetch-url https://github.com/abacusai/deepagent-releases/releases/download/VERSION/abacusai-agent-cli-linux-x64-VERSION.tar.gz

# Then rebuild your system
sudo nixos-rebuild switch --flake .#rocinante
```

## Current Version

Check the current version in `flake.nix` or run:
```bash
nix eval /home/kosta/nix-config/flakes/abacusai-fhs#packages.x86_64-linux.default.name
```

## Architecture

This flake:
- **Sources**: Downloads tarballs from GitHub releases (abacusai/deepagent-releases)
- **Patching**: Uses `autoPatchelfHook` to fix binary dependencies
- **FHS Environment**: Wraps binaries in an FHS environment for full compatibility
- **Desktop Entry**: Creates a `.desktop` file for the GUI application

## References

- [AbacusAI Official Site](https://abacus.ai/)
- [DeepAgent Releases](https://github.com/abacusai/deepagent-releases/releases)

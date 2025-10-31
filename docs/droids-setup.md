# FactoryAI Droids IDE Setup Guide

This guide explains how to use the FactoryAI Droids IDE integration in your NixOS configuration.

## Overview

FactoryAI Droids is an AI-powered coding assistant CLI that works with any LLM, in any IDE, and supports both local and remote development environments.

## Architecture

The integration consists of:

1. **Separate Flake** (`flakes/droids/`): A standalone flake that packages Droids IDE
2. **NixOS Module** (`modules/droids.nix`): Configuration module to enable/disable Droids
3. **Main Flake Integration**: The droids flake is imported as an input in your main `flake.nix`

## Installation

### 1. Enable the Module

Add to your NixOS configuration (e.g., in `hosts/rocinante/configuration.nix`):

```nix
{
  programs.droids.enable = true;
}
```

### 2. Rebuild Your System

```bash
sudo nixos-rebuild switch
```

### 3. Start Using Droids

Navigate to any project directory and run:

```bash
droid
```

On first launch, you'll be prompted to authenticate via your browser.

## How It Works

The Droids flake directly fetches the official Droids CLI binary (v0.22.3) and ripgrep from FactoryAI's download servers. These binaries are:

1. Verified with SHA256 checksums
2. Packaged in an FHS (Filesystem Hierarchy Standard) environment
3. Wrapped with all required dependencies

This approach ensures:
- **No manual installation needed** - everything is declarative
- **Reproducible builds** - SHA256 hashes ensure identical binaries
- **Full compatibility** - FHS environment provides expected system layout

## Module Options

The module supports the following options in `modules/droids.nix`:

```nix
programs.droids = {
  enable = true;              # Enable/disable Droids
  package = <derivation>;     # Override the droids package (advanced)
};
```

## Dependencies

The FHS wrapper automatically provides:

- Core utilities: curl, git, gnused, gawk, coreutils, findutils
- Browser integration: xdg-utils (required for Linux)
- Development tools: Node.js, Python3, GCC
- ripgrep: Bundled from Factory.ai's servers

## Files and Directories

- `~/.factory/` - Droids data directory
- `~/.factory/bin/rg` - Ripgrep binary (managed by Droids)
- `~/.config/factory/` - User configuration

## Troubleshooting

### Browser doesn't open on first run

Ensure `xdg-utils` is working:
```bash
xdg-open https://factory.ai
```

### Command not found

Ensure the package is installed:
```bash
which droid
```

If not found, rebuild your system:
```bash
sudo nixos-rebuild switch
```

## Updating Droids

To update to a new version:

1. Edit `flakes/droids/flake.nix` and update the `version` variable
2. Set the SHA256 hashes to placeholder values
3. Build to get the correct hashes: `nix build --impure`
4. Update the hashes in the flake
5. Rebuild your system: `sudo nixos-rebuild switch`

## Uninstalling

To remove Droids:

1. Disable in your configuration:
   ```nix
   programs.droids.enable = false;
   ```

2. Rebuild:
   ```bash
   sudo nixos-rebuild switch
   ```

3. Optionally remove configuration files:
   ```bash
   rm -rf ~/.factory ~/.config/factory
   ```

## References

- [FactoryAI Website](https://factory.ai)
- [Official Documentation](https://docs.factory.ai)
- [CLI Quickstart](https://docs.factory.ai/cli/getting-started/quickstart)
- [Droids Flake](../flakes/droids/)
- [Droids Module](../modules/droids.nix)

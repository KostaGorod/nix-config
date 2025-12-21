# Warp Terminal FHS Environment

This flake provides Warp Terminal wrapped in a full FHS (Filesystem Hierarchy Standard) environment, giving it complete access to:

- System defaults and environment variables
- sudo and system utilities
- All shells (bash, zsh, fish, nushell)
- Development tools (git, openssh, curl, etc.)
- SSL certificates and locale support

## Why FHS?

Warp Terminal benefits from an FHS environment because:

1. **Shell Access**: Can properly detect and use all installed shells
2. **System Integration**: Full access to sudo and system utilities
3. **Development Workflow**: Seamless access to git, ssh, and other dev tools
4. **Environment Preservation**: Inherits your user environment and dotfiles

## Features

The FHS wrapper includes:

- **Shells**: bash, zsh, fish, nushell
- **System Tools**: sudo, coreutils, findutils, grep, sed, awk
- **Development**: git, openssh, curl, wget
- **Security**: SSL certificates, OpenSSL
- **User Environment**: Preserves HOME and sources user profiles

## Usage

The flake is used via the main nix-config:

```nix
inputs.warp-fhs.packages.${pkgs.system}.default
```

You can also run it directly:

```bash
nix run path:./flakes/warp-fhs
```

Or from the main flake:

```bash
nix run .#warp-fhs
```

## Structure

- `flake.nix`: Main flake definition with FHS environment configuration
- `flake.lock`: Locked dependencies (auto-generated)
- `README.md`: This file

## Updating

To update the nixpkgs version used:

```bash
cd flakes/warp-fhs
nix flake update
```

Then rebuild your NixOS configuration to apply the update.

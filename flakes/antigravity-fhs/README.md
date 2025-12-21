# Antigravity IDE Flake

This is a local wrapper flake for [Google Antigravity IDE](https://antigravity.google/) - an AI-powered development environment.

## What is this?

This flake re-exports the `antigravity` package from the community-maintained [jacopone/antigravity-nix](https://github.com/jacopone/antigravity-nix) repository, which provides auto-updating Nix packages for Antigravity IDE.

## Why a wrapper flake?

This wrapper flake provides several benefits:
1. **Easy updates**: Update only Antigravity without re-downloading your entire nixpkgs
2. **Version pinning**: Control when to update independently from your main system
3. **Consistent naming**: Provides both `antigravity` and `antigravity-fhs` aliases

## Usage

The package is already integrated into the rocinante profile in the main nix-config.

To run Antigravity directly:
```bash
nix run /home/kosta/nix-config/flakes/antigravity-fhs
```

Or with specific package name:
```bash
nix run /home/kosta/nix-config/flakes/antigravity-fhs#antigravity
```

## Updating Antigravity

To update to the latest version of Antigravity IDE:

```bash
# Update just the antigravity flake (fast, ~1-2 MB download)
cd /home/kosta/nix-config
nix flake lock --update-input antigravity-fhs/antigravity-nix

# Or update the entire flakes/antigravity-fhs directory
nix flake update flakes/antigravity-fhs

# Then rebuild your system
sudo nixos-rebuild switch --flake .#rocinante
```

The upstream `jacopone/antigravity-nix` repository auto-updates 3 times per week, so you'll get new versions within 48 hours of official releases.

## Current Version

Check the current version:
```bash
nix eval /home/kosta/nix-config/flakes/antigravity-fhs#packages.x86_64-linux.default.version
```

## Architecture

This flake:
- **Inputs**: `antigravity-nix` from GitHub (jacopone/antigravity-nix)
- **Outputs**: Re-exported packages with aliases (`default`, `antigravity`, `antigravity-fhs`)
- **No heavy dependencies**: Uses nixpkgs from the upstream flake, avoiding duplicate downloads

## References

- [Antigravity IDE Official Site](https://antigravity.google/)
- [Antigravity Release Notes](https://antigravity.google/releases)
- [Community Nix Package Repository](https://github.com/jacopone/antigravity-nix)

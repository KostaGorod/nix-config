# FactoryAI Droids IDE Flake

This flake provides a NixOS package for FactoryAI Droids IDE - an AI coding agent CLI tool.

## Overview

FactoryAI Droids is an AI-powered coding assistant that works with any LLM, in any IDE, in local or remote environments.

## Installation

This flake is integrated into your NixOS configuration. To enable it:

1. Enable the module in your configuration:
   ```nix
   programs.droids.enable = true;
   ```

2. Rebuild your system:
   ```bash
   sudo nixos-rebuild switch
   ```

3. Start using Droids:
   ```bash
   droid
   ```

## How It Works

This flake directly fetches the official Droids CLI binary from FactoryAI's download servers and packages it in an FHS environment with all necessary dependencies.

**Components:**
- **Droids CLI binary** (v0.22.3): Fetched from `https://downloads.factory.ai/factory-cli/releases/`
- **ripgrep binary**: Fetched from `https://downloads.factory.ai/ripgrep/` (required by Droids)
- **FHS environment**: Provides all runtime dependencies (curl, git, xdg-utils, Node.js, Python, GCC, etc.)

The binaries are verified with SHA256 checksums and wrapped in a Filesystem Hierarchy Standard (FHS) environment for compatibility.

## Usage

After installation:

- Run `droid` in any project directory to start an AI coding session
- The first time you run it, you'll be prompted to authenticate via your browser
- You start with free tokens to try the platform

## Dependencies

The FHS wrapper automatically includes:
- curl, git, coreutils, findutils
- xdg-utils (for browser opening on Linux)
- Common development tools (Node.js, Python, GCC)
- ripgrep (bundled from Factory.ai)

## Supported Platforms

- x86_64-linux ✓
- aarch64-linux (hashes need to be updated on first build)

## Updating

To update to a new version of Droids:

1. Update the `version` variable in `flake.nix`
2. Set hashes to placeholder values
3. Run `nix build --impure` to get the correct hashes
4. Update the hashes in the `platformInfo` attribute set

## References

- [FactoryAI Website](https://factory.ai)
- [FactoryAI Documentation](https://docs.factory.ai)
- [CLI Quickstart](https://docs.factory.ai/cli/getting-started/quickstart)

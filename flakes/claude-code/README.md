# Claude Code Flake

Separate flake for Anthropic Claude Code CLI.

## Update

```bash
nix flake lock --update-input claude-code
sudo nixos-rebuild switch --flake .#rocinante
```

# Workstation profile
# Complete desktop environment with AI tools, productivity apps, etc.
{ ... }:
{
  imports = [
    ../modules/nixos/services.nix
    ../modules/nixos/desktop.nix
    ../modules/nixos/tailscale.nix
    ../modules/nixos/opencode.nix
    ../modules/nixos/claude-code.nix
    ../modules/nixos/droids.nix
    ../modules/nixos/bitwarden.nix
  ];

  # Enable AI tools
  programs.opencode.enable = true;
  programs.claude-code.enable = true;
  programs.droids.enable = true;
  programs.bitwarden.enable = true;

  # Desktop apps
  programs.spotify-patched.enable = true;
}

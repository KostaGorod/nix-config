# Kosta's NixOS user configuration
# Aggregates user packages and system-level program defaults
{ ... }:
{
  imports = [
    ./packages.nix
    ./programs/git.nix
    ./programs/shell.nix
    ./programs/editors.nix
    ./programs/services.nix
    ./programs/fuzzel.nix
    ./programs/zen-browser.nix
  ];
}

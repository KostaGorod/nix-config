# User configuration for kosta - NixOS module
# Aggregates packages and program configs
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

# User configuration for kosta
# Aggregates packages and program configs
{ pkgs, ... }:
let
  inherit (pkgs.stdenv) isDarwin;
  homeDir = if isDarwin then "/Users/" else "/home/";
  username = "kosta";
in
{
  imports = [
    ./packages.nix
    ./programs/git.nix
    ./programs/shell.nix
    ./programs/editors.nix
    ./programs/services.nix
  ];

  home = {
    inherit username;
    homeDirectory = homeDir + username;
    stateVersion = "24.05";
  };

  # Let Home Manager manage itself
  programs.home-manager.enable = true;
}

# Git configuration for kosta
{ pkgs, inputs, ... }:
let
  pkgs-unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };
in
{
  programs.git = {
    package = pkgs.gitFull;
    enable = true;
  };

  environment.etc."gitconfig".text = ''
    [user]
      name = Kosta Gorod
      email = 35299380+KostaGorod@users.noreply.github.com

    [credential]
      helper = ${pkgs.gitFull.override { withLibsecret = true; }}/bin/git-credential-libsecret

    [core]
    editor = helix
  '';

  # GitHub CLI
  environment.systemPackages = [ pkgs-unstable.gh ];
}

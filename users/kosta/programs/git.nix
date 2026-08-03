# Git configuration for kosta
{ inputs, pkgs, ... }:
let
  git = pkgs.gitFull.override { withLibsecret = true; };
  gitConfig = pkgs.writeText "kosta-gitconfig" ''
    [user]
      name = Kosta Gorod
      email = 35299380+KostaGorod@users.noreply.github.com

    [credential]
      helper = ${git}/bin/git-credential-libsecret

    [core]
      editor = hx
  '';
  pkgs-unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };
in
{
  programs.git = {
    package = git;
    enable = true;
  };

  systemd.tmpfiles.rules = [ "L+ /home/kosta/.gitconfig - kosta users - ${gitConfig}" ];

  # GitHub CLI
  users.users.kosta.packages = [ pkgs-unstable.gh ];
}

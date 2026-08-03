# Git configuration for kosta
{ inputs, ... }:
{
  nixos.modules.kosta =
    { pkgs, ... }:
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
      systemd.tmpfiles.rules = [ "L+ /home/kosta/.gitconfig - kosta users - ${gitConfig}" ];

      # GitHub CLI
      users.users.kosta.packages = [ pkgs-unstable.gh ];
    };
}

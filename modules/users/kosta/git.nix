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
          helper = ${pkgs.git-credential-oauth}/bin/git-credential-oauth

        [credential "https://gist.github.com"]
          helper = ""
          helper = ${pkgs-unstable.gh}/bin/gh auth git-credential

        [credential "https://github.com"]
          helper = ""
          helper = ${pkgs-unstable.gh}/bin/gh auth git-credential

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
      environment.etc."xdg/gh/config.yml".text = ''
        aliases: {}
        editor: ""
        git_protocol: https
        version: '1'
      '';

      users.users.kosta.packages = [
        pkgs.git-credential-oauth
        pkgs-unstable.gh
      ];
    };
}

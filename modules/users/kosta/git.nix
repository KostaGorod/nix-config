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
      ghConfig = pkgs.writeText "kosta-gh-config.yml" ''
        aliases: {}
        editor: ""
        git_protocol: https
        version: "1"
      '';
      pkgs-unstable = import inputs.nixpkgs-unstable {
        inherit (pkgs.stdenv.hostPlatform) system;
        config.allowUnfree = true;
      };
    in
    {
      systemd.tmpfiles.rules = [ "L+ /home/kosta/.gitconfig - kosta users - ${gitConfig}" ];

      system.activationScripts.kostaGhConfigRepair = {
        deps = [
          "users"
          "homeManagerMigration"
        ];
        text = ''
          configDir=/home/kosta/.config/gh
          configFile=$configDir/config.yml
          legacyTarget=/etc/xdg/gh/config.yml

          if [ -L "$configFile" ]; then
            target="$(${pkgs.coreutils}/bin/readlink "$configFile")"
            if [ "$target" = "$legacyTarget" ]; then
              ${pkgs.coreutils}/bin/rm -- "$configFile"
            else
              echo "gh config repair: refusing unexpected link $configFile -> $target" >&2
            fi
          fi

          if [ ! -e "$configFile" ] && [ ! -L "$configFile" ]; then
            if [ -L "$configDir" ] || { [ -e "$configDir" ] && [ ! -d "$configDir" ]; }; then
              echo "gh config repair: refusing unexpected config directory $configDir" >&2
            else
              if [ ! -e "$configDir" ]; then
                ${pkgs.coreutils}/bin/mkdir -p "$configDir"
                ${pkgs.coreutils}/bin/chown kosta:users "$configDir"
                ${pkgs.coreutils}/bin/chmod 0700 "$configDir"
              fi
              ${pkgs.coreutils}/bin/install -m 0600 -o kosta -g users ${ghConfig} "$configFile"
            fi
          fi
        '';
      };

      users.users.kosta.packages = [
        pkgs.git-credential-oauth
        pkgs-unstable.gh
      ];
    };
}

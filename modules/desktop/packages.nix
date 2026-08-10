# Desktop environment module
# Fonts, themes, GUI utilities, graphics
{ inputs, ... }:
{
  nixos.modules.workstation =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.antigravity;
    in
    {
      options.programs.antigravity = {
        enable = lib.mkEnableOption "Antigravity IDE";

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.antigravity.packages.${pkgs.stdenv.hostPlatform.system}.default;
          description = "The Antigravity package to use";
        };
      };

      config = {
        # Fonts
        fonts.packages = with pkgs; [
          helvetica-neue-lt-std
          fragment-mono
          aileron
        ];

        # Desktop utilities
        environment.systemPackages =
          with pkgs;
          [
            # Themes
            numix-cursor-theme

            # GUI utilities
            gnome-calculator

            # Virtual keyboard
            maliit-keyboard
            maliit-framework

            # Graphics tools
            vulkan-tools

            # Media tools
            easyeffects

            # Python environment
            (python3.withPackages (
              ps: with ps; [
                ipython
                bpython
                requests
                pyyaml
              ]
            ))

            # CLI tools for desktop use
            sshuttle
            jqp
            jp
            httpie
            borgbackup

          ]
          ++ lib.optionals cfg.enable [
            (makeDesktopItem {
              name = "antigravity-custom";
              desktopName = "Antigravity IDE";
              comment = "Google Antigravity AI-powered development environment";
              exec = "${cfg.package}/bin/antigravity %U";
              icon = "code";
              terminal = false;
              type = "Application";
              categories = [
                "Development"
                "IDE"
              ];
            })
            (writeShellScriptBin "antigravity" ''
              exec ${cfg.package}/bin/antigravity "$@"
            '')
          ];
      };
    };
}

{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.programs.opencode;

  # Import from nix-ai-tools
  inherit (inputs) nix-ai-tools;
  opencode-pkg = nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.opencode;

  opencode-wrapper = pkgs.symlinkJoin {
    name = "opencode-wrapper";
    paths = [
      cfg.package
    ];
    postBuild = ''
      rm -f $out/bin/opencode

      cat > $out/bin/opencode <<'EOF'
      #!${pkgs.bash}/bin/bash
      set -euo pipefail

      if [[ $# -ge 1 && "$1" == "desktop" ]]; then
        shift || true

        if command -v opencode-desktop >/dev/null 2>&1; then
          exec opencode-desktop "$@"
        fi

        echo "opencode-desktop is not installed or not on PATH." >&2
        echo "Install it from https://opencode.ai/download and try again." >&2
        exit 1
      fi

      exec ${cfg.package}/bin/opencode "$@"
      EOF

      chmod +x $out/bin/opencode
    '';
  };
in
{
  options.programs.opencode = {
    enable = lib.mkEnableOption "OpenCode AI coding agent";

    package = lib.mkOption {
      type = lib.types.package;
      default = opencode-pkg;
      description = "The OpenCode package to use";
    };

    desktop = {
      enable = lib.mkEnableOption "OpenCode Desktop launcher via 'opencode desktop'";

      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        description = "Optional opencode-desktop package to add to PATH";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Add opencode (with wrapper) to system packages
    environment.systemPackages = [
      opencode-wrapper
    ]
    ++ lib.optionals (cfg.desktop.enable && cfg.desktop.package != null) [
      cfg.desktop.package
    ];

    # Create necessary directories for OpenCode
    systemd.tmpfiles.rules = [
      "d %h/.config/opencode 0755 - - -"
      "d %h/.cache/opencode 0755 - - -"
      "d %h/.local/share/opencode 0755 - - -"
    ];

    # Add session variables for users
    environment.sessionVariables = {
      OPENCODE_CONFIG_HOME = "$HOME/.config/opencode";
      OPENCODE_AUTO_SHARE = "false";
    };
  };
}

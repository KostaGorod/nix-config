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
in
{
  options.programs.opencode = {
    enable = lib.mkEnableOption "OpenCode AI coding agent";

    package = lib.mkOption {
      type = lib.types.package;
      default = opencode-pkg;
      description = "The OpenCode package to use";
    };
  };

  config = lib.mkIf cfg.enable {
    # Add opencode to system packages
    environment.systemPackages = [
      cfg.package
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
    };
  };
}

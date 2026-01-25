{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.programs.opencode;

  # Import from nix-ai-tools and override with latest version
  nix-ai-tools = inputs.nix-ai-tools;
  opencode-base = nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.opencode;

  # Override to v1.1.12 (released 2026-01-10)
  opencode-pkg = opencode-base.overrideAttrs (old: rec {
    version = "1.1.12";
    src = pkgs.fetchurl {
      url = "https://github.com/anomalyco/opencode/releases/download/v${version}/opencode-linux-x64.tar.gz";
      hash = "sha256-eiFuBbT1Grz1UBrGfg22z2AdCvE/6441vLVDD6L9DgE=";
    };
  });
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

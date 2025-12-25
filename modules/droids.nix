{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.programs.droids;

  # Import from nix-ai-tools
  nix-ai-tools = inputs.nix-ai-tools;
  droids-pkg = nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.droid;
in
{
  options.programs.droids = {
    enable = lib.mkEnableOption "FactoryAI Droids IDE";

    package = lib.mkOption {
      type = lib.types.package;
      default = droids-pkg;
      description = "The Droids package to use";
    };
  };

  config = lib.mkIf cfg.enable {
    # Add droids and required dependencies to system packages
    environment.systemPackages = with pkgs; [
      cfg.package
      xdg-utils
    ];

    # Create necessary directories for Droids
    systemd.tmpfiles.rules = [
      "d %h/.factory 0755 - - -"
      "d %h/.factory/bin 0755 - - -"
      "d %h/.config/factory 0755 - - -"
    ];

    # Add session variables for users
    environment.sessionVariables = {
      FACTORY_CONFIG_HOME = "$HOME/.config/factory";
    };
  };
}

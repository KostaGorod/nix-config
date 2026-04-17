{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.programs.kimi-cli;

  # Import from kimi-cli flake
  inherit (inputs) kimi-cli;
  kimi-cli-pkg = kimi-cli.packages.${pkgs.stdenv.hostPlatform.system}.kimi-cli;
in
{
  options.programs.kimi-cli = {
    enable = lib.mkEnableOption "MoonshotAI Kimi CLI";

    package = lib.mkOption {
      type = lib.types.package;
      default = kimi-cli-pkg;
      description = "The Kimi CLI package to use";
    };
  };

  config = lib.mkIf cfg.enable {
    # Add kimi-cli to system packages
    environment.systemPackages = [
      cfg.package
    ];
  };
}

{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.programs.gemini-cli;

  # Import from llm-agents.nix
  inherit (inputs) llm-agents;
  gemini-cli-pkg = llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.gemini-cli;
in
{
  options.programs.gemini-cli = {
    enable = lib.mkEnableOption "Google Gemini CLI";

    package = lib.mkOption {
      type = lib.types.package;
      default = gemini-cli-pkg;
      description = "The Gemini CLI package to use";
    };
  };

  config = lib.mkIf cfg.enable {
    # Add gemini-cli to system packages
    environment.systemPackages = [
      cfg.package
    ];
  };
}

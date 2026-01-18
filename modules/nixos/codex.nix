{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.programs.codex;

  # Import from nix-ai-tools
  inherit (inputs) nix-ai-tools;
  codex-pkg = nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.codex;
in
{
  options.programs.codex = {
    enable = lib.mkEnableOption "Numtide Codex AI assistant";

    package = lib.mkOption {
      type = lib.types.package;
      default = codex-pkg;
      description = "The Codex package to use";
    };
  };

  config = lib.mkIf cfg.enable {
    # Add codex to system packages
    environment.systemPackages = [
      cfg.package
    ];
  };
}

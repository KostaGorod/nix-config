# AbacusAI DeepAgent module
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.programs.abacusai;
in
{
  options.programs.abacusai = {
    enable = lib.mkEnableOption "AbacusAI DeepAgent desktop client and CLI";

    package = lib.mkOption {
      type = lib.types.package;
      inherit (inputs.abacusai-fhs.packages.${pkgs.stdenv.hostPlatform.system}) default;
      description = "The AbacusAI package to use";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
    ];

    # Create necessary directories for AbacusAI
    systemd.tmpfiles.rules = [
      "d %h/.config/abacusai 0755 - - -"
      "d %h/.cache/abacusai 0755 - - -"
    ];
  };
}

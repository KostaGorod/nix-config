{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.programs.abacusai;
  abacusai-pkgs = inputs.abacusai-fhs.packages.${pkgs.system};
in {
  options.programs.abacusai = {
    enable = lib.mkEnableOption "Abacus.AI DeepAgent desktop client and CLI";

    gui = lib.mkOption {
      type = lib.types.package;
      default = abacusai-pkgs.gui;
      description = "The AbacusAI GUI package.";
    };

    cli = lib.mkOption {
      type = lib.types.package;
      default = abacusai-pkgs.cli;
      description = "The AbacusAI CLI package.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      cfg.gui
      cfg.cli
    ];
  };
}


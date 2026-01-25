{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.programs.bitwarden;

  pkgs-unstable = import inputs.nixpkgs-unstable {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
in
{
  options.programs.bitwarden = {
    enable = lib.mkEnableOption "Bitwarden desktop password manager";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs-unstable.bitwarden-desktop;
      description = "The Bitwarden desktop package to use";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
    ];
  };
}

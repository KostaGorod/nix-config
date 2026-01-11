{ config, pkgs, lib, inputs, ... }:

let
  memvid = pkgs.callPackage ../pkgs/memvid/default.nix { };
in
{
  options.services.memvid = {
    enable = lib.mkEnableOption "Memvid service";
  };

  config = lib.mkIf config.services.memvid.enable {
    environment.systemPackages = [ memvid ];
    
    # We can also add a devShell here if needed, 
    # but environment.systemPackages makes it available as a command.
  };
}

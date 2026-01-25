{
  pkgs,
  lib,
  tests,
  ...
}:

let
  module = import ./desktop.nix { inherit pkgs lib; };
in
{
  checks = {
    xserver-enabled = tests.runTest "xserver" module.services.xserver.enable;
    sddm-enabled = tests.runTest "sddm" module.services.displayManager.sddm.enable;
  };
}

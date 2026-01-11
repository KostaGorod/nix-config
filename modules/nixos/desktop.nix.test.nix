{
  pkgs,
  lib,
  tests,
  inputs,
  ...
}:

let
  module = import ./desktop.nix { inherit pkgs lib inputs; };
in
{
  checks = {
    # desktop.nix contains fonts and system packages
    has-fonts = tests.runTest "fonts" (module ? fonts.packages);
    has-packages = tests.runTest "desktop-packages" (module ? environment.systemPackages);
  };
}

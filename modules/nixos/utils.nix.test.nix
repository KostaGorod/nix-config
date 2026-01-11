{
  pkgs,
  lib,
  tests,
  ...
}:

let
  module = import ./utils.nix { inherit pkgs lib; };
in
{
  checks = {
    # Check that ripgrep and jq are present in systemPackages
    has-ripgrep = tests.runTest "ripgrep" (
      lib.any (p: p.name == pkgs.ripgrep.name) module.environment.systemPackages
    );
    has-jq = tests.runTest "jq" (lib.any (p: p.name == pkgs.jq.name) module.environment.systemPackages);
  };
}

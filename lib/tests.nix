# VM test utilities for NixOS configuration
{
  pkgs,
  lib,
  nixpkgs,
  ...
}:

{
  # Import and configure a NixOS VM test
  mkVMTest =
    testPath:
    import (nixpkgs + "/nixos/tests/make-test-python.nix") (import testPath) {
      inherit pkgs;
      inherit (pkgs) system;
    };

  # Run multiple VM tests and combine results
  mkVMTests =
    testPaths:
    lib.listToAttrs (
      map (path: {
        name = lib.removeSuffix ".nix" (builtins.baseNameOf path);
        value = import (nixpkgs + "/nixos/tests/make-test-python.nix") (import path) {
          inherit pkgs;
          inherit (pkgs) system;
        };
      }) testPaths
    );
}

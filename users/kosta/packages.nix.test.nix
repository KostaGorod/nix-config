{
  pkgs,
  lib,
  tests,
  inputs,
  ...
}:

let
  module = import ./packages.nix { inherit pkgs lib inputs; };
in
{
  checks = {
    packages-is-list = tests.runTest "packages-list" (builtins.isList module.home.packages);
  };
}

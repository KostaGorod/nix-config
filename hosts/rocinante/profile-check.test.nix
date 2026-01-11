{
  pkgs,
  lib,
  tests,
  ...
}:

let
  module = import ../../profiles/workstation.nix { inherit pkgs lib; };
in
{
  checks = {
    is-modular = tests.runTest "profile-modular" (builtins.isList module.imports);
  };
}

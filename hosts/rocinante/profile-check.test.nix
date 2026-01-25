{
  pkgs,
  lib,
  tests,
  inputs,
  ...
}:

let
  module = import ../../profiles/workstation.nix {
    inherit pkgs lib inputs;
    config = { };
  };
in
{
  checks = {
    is-modular = tests.runTest "profile-modular" (builtins.isList module.imports);
  };
}

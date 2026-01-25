{
  pkgs,
  lib,
  tests,
  inputs,
  ...
}:

let
  module = import ./default.nix {
    inherit pkgs lib inputs;
    config = { };
    modulesPath = "";
  };
in
{
  checks = {
    hostname-set = tests.runTest "hostname" (module.networking.hostName == "rocinante");
    user-is-normal = tests.runTest "user-type" module.users.users.kosta.isNormalUser;
  };
}

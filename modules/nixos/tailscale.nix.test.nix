{
  pkgs,
  lib,
  tests,
  ...
}:

let
  module = import ./tailscale.nix { inherit pkgs lib; };
in
{
  checks = {
    tailscale-enabled = tests.runTest "tailscale" module.services.tailscale.enable;
    dnsmasq-enabled = tests.runTest "dnsmasq" module.services.dnsmasq.enable;
    local-resolver = tests.runTest "resolver" module.networking.resolvconf.useLocalResolver;
  };
}

{
  pkgs,
  lib,
  tests,
  ...
}:

let
  module = import ./services.nix { inherit pkgs lib; };
in
{
  checks = {
    # Logic validation: ensure critical services are enabled in the module definition
    fwupd-enabled = tests.runTest "fwupd" module.services.fwupd.enable;
    printing-enabled = tests.runTest "printing" module.services.printing.enable;
    audio-enabled = tests.runTest "audio" module.services.pipewire.enable;
    tlp-enabled = tests.runTest "tlp" module.services.tlp.enable;
  };
}

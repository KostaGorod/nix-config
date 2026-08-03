_: {
  nixos.modules.workstation = {
    imports = [
      ../profiles/workstation.nix
      ../de/plasma6.nix
      ../de/cosmic.nix
      ../modules/nixos/utils.nix
      ../modules/nixos/cliphist.nix
      ../modules/nixos/spotify.nix
      ../modules/nixos/moonlight-qt.nix
      ../modules/nixos/tlp-power-profiles-bridge.nix
    ];
  };
}

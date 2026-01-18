{ pkgs, ... }:
{
  nixpkgs.overlays = [
    (import ../../overlays/spotify-overlay.nix)
  ];

  environment.systemPackages = with pkgs; [
    spotify-with-spotx
  ];
}

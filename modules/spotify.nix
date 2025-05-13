{pkgs, lib, ...}:
{
  nixpkgs.overlays = [
      (import ../overlays/spotify-overlay.nix)
    ];

  environment.systemPackages = with pkgs; [
    spotify-with-spotx
  ];
}
# { config, pkgs, ... }:
# {
#   # simple example of how to override a package
#   #
#   # environment.systemPackages = with pkgs; [
#   #   (pkgs.spotify.overrideAttrs (old: {
#   #     nativeBuildInputs = old.nativeBuildInputs ++ (with old; [util-linux perl unzip zip curl]);
#   #     }))
#   # ];
#   #
#   # }
#   let
#     spotify-with-patch = pkgs.spotify
#     })
#   in
#   {
#     environment.systemPackages = with pkgs; [
#       spotify-with-patch (inh)
#     ];
#   };
# }

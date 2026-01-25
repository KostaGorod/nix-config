# Spotify with SpotX ad-blocker patch
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.spotify-patched;
  
  spotify-with-spotx = pkgs.spotify.overrideAttrs (old: 
    let
      spotx = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/SpotX-Official/SpotX-Bash/a814894e8cca3282a0ad79f30896ec4b01544d4e/spotx.sh";
        hash = "sha256-ZYep5dmg07ae+3kvN+BTKDB2Ky76Xe2fXR3VKKnDMsQ=";
      };
    in {
      nativeBuildInputs = old.nativeBuildInputs ++ (with pkgs; [
        util-linux perl unzip zip curl
      ]);
      
      unpackPhase = builtins.replaceStrings
        [ "runHook postUnpack" ]
        [ ''
            patchShebangs --build ${spotx}
            runHook postUnpack
          '' ]
        old.unpackPhase;
      
      installPhase = builtins.replaceStrings
        [ "runHook postInstall" ]
        [ ''
            bash ${spotx} -f -P "$out/share/spotify"
            runHook postInstall
          '' ]
        old.installPhase;
    });
in
{
  options.programs.spotify-patched = {
    enable = lib.mkEnableOption "Spotify with SpotX ad-blocker patch";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ spotify-with-spotx ];
  };
}

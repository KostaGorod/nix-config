# copy-paste from https://github.com/oskardotglobal/.dotfiles/blob/nix/overlays/spotx.nix
final: prev: let
  spotx = prev.fetchurl {
    url = "https://raw.githubusercontent.com/SpotX-Official/SpotX-Bash/a814894e8cca3282a0ad79f30896ec4b01544d4e/spotx.sh";
    hash = "sha256-ZYep5dmg07ae+3kvN+BTKDB2Ky76Xe2fXR3VKKnDMsQ=";
    #sha256 = prev.lib.fakeSha256;
  };
in {
  spotify-with-spotx = prev.spotify.overrideAttrs (old: {
    nativeBuildInputs = old.nativeBuildInputs ++ (with prev; [util-linux perl unzip zip curl]);

    unpackPhase =
      builtins.replaceStrings
      ["runHook postUnpack"]
      [
        ''
          patchShebangs --build ${spotx}
          runHook postUnpack
        ''
      ]
      old.unpackPhase;

    installPhase =
      builtins.replaceStrings
      ["runHook postInstall"]
      [
        ''
          bash ${spotx} -f -P "$out/share/spotify"
          runHook postInstall
        ''
      ]
      old.installPhase;
  });
}

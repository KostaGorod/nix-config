{
  appimageTools,
  fetchurl,
  lib,
}:
let
  pname = "orca-ide";
  version = "1.4.179";
  src = fetchurl {
    url = "https://github.com/stablyai/orca/releases/download/v${version}/orca-linux.AppImage";
    hash = "sha256-B4CEhW22bSmya1dguIAo3pWv/NdxQxNZ7uNpJCl7EN8=";
  };
  appimageContents = appimageTools.extractType2 { inherit pname version src; };
in
appimageTools.wrapType2 rec {
  inherit pname version src;

  # The computer-use sidecar invokes python3 inside the AppImage FHS sandbox.
  # Keep the downloaded AppImage unchanged and add only the missing runtime.
  extraPkgs = pkgs: [
    pkgs.python3
    pkgs.python3Packages.pygobject3
    pkgs.gobject-introspection
    pkgs.at-spi2-core
  ];

  extraInstallCommands = ''
    install -m 444 -D ${appimageContents}/orca-ide.desktop $out/share/applications/orca-ide.desktop
    install -m 444 -D ${appimageContents}/orca-ide.png $out/share/icons/hicolor/512x512/apps/orca-ide.png
    substituteInPlace $out/share/applications/orca-ide.desktop \
      --replace-fail 'Exec=AppRun' "Exec=$out/bin/orca-ide"
  '';

  meta = {
    description = "ADE for working with a fleet of parallel coding agents";
    homepage = "https://onorca.dev";
    license = lib.licenses.mit;
    mainProgram = "orca-ide";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}

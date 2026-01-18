{ lib, rustPlatform, cliphist, rofi, wl-clipboard, zenity, makeWrapper }:

rustPlatform.buildRustPackage {
  pname = "clipboard-picker";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram $out/bin/clipboard-picker \
      --set CLIPHIST_BIN "${cliphist}/bin/cliphist" \
      --set ROFI_BIN "${rofi}/bin/rofi" \
      --set WL_COPY_BIN "${wl-clipboard}/bin/wl-copy" \
      --set WL_PASTE_BIN "${wl-clipboard}/bin/wl-paste" \
      --set ZENITY_BIN "${zenity}/bin/zenity"
  '';

  meta = with lib; {
    description = "Clipboard history picker with rofi integration and keyboard shortcuts";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}

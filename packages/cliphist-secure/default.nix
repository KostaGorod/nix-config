{
  gnumake,
  lib,
  libsecret,
  perl,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "cliphist-secure";
  version = "0.2.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  strictDeps = true;
  nativeBuildInputs = [
    gnumake
    perl
  ];

  CLIPHIST_SECRET_TOOL = "${libsecret}/bin/secret-tool";

  meta = {
    description = "SQLCipher-encrypted clipboard history backed by GNOME Keyring";
    license = lib.licenses.mit;
    mainProgram = "cliphist";
    platforms = lib.platforms.linux;
  };
}

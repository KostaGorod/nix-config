{ lib, rustPlatform, fetchCrate, pkg-config, zstd, openssl, stdenv, darwin }:

rustPlatform.buildRustPackage rec {
  pname = "memvid-cli";
  version = "2.0.133";

  src = fetchCrate {
    inherit pname version;
    sha256 = "sha256-DsJcqd+VwCzXm2nQXdopbia+ksJS3+So5D7anEXetfU=";
  };

  cargoHash = "sha256-2/I1gu6/hcQq/ZD6yI78sC9iOavmK3hRQRoNzT+f3xA=";

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [ zstd openssl ] ++ lib.optionals stdenv.isDarwin [ darwin.apple_sdk.frameworks.Security ];

  meta = with lib; {
    description = "Command-line interface for Memvid - AI memory with crash-safe, single-file storage";
    homepage = "https://github.com/memvid/memvid";
    license = lib.licenses.asl20;
    mainProgram = "memvid";
  };
}

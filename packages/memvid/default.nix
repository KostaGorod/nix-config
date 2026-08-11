{
  lib,
  rustPlatform,
  fetchCrate,
  pkg-config,
  zstd,
  openssl,
  onnxruntime,
  stdenv,
  darwin,
}:

rustPlatform.buildRustPackage rec {
  pname = "memvid-cli";
  version = "2.0.133";

  src = fetchCrate {
    inherit pname version;
    hash = "sha256-DsJcqd+VwCzXm2nQXdopbia+ksJS3+So5D7anEXetfU=";
  };

  cargoHash = "sha256-2/I1gu6/hcQq/ZD6yI78sC9iOavmK3hRQRoNzT+f3xA=";
  buildNoDefaultFeatures = true;
  buildFeatures = [
    "parallel_segments"
    "temporal_track"
  ];

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [
    zstd
    openssl
    onnxruntime
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ darwin.apple_sdk.frameworks.Security ];

  env = {
    ORT_LIB_LOCATION = "${onnxruntime}/lib";
    ORT_PREFER_DYNAMIC_LINK = "1";
  };

  meta = {
    description = "Command-line interface for Memvid local memory files";
    homepage = "https://github.com/memvid/memvid";
    license = lib.licenses.asl20;
    mainProgram = "memvid";
    platforms = lib.platforms.unix;
  };
}

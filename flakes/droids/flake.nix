{
  description = "FactoryAI Droids IDE - AI Coding Agents CLI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          version = "0.22.3";

          # Map Nix system to Factory.ai platform/architecture and hashes
          platformInfo = {
            "x86_64-linux" = {
              platform = "linux";
              arch = "x64";
              droidSha256 = "sha256-zoLbZ1OEH2w81yXr0jZnsAyoc+DIRz8St653ohoy8Ug=";
              rgSha256 = "sha256-viR2yXY0K5IWYRtKhMG8LsZIjsXHkeoBmhMnJ2RO8Zw=";
            };
            "aarch64-linux" = {
              platform = "linux";
              arch = "arm64";
              # TODO: Update these hashes when building on aarch64-linux
              droidSha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
              rgSha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
            };
          };

          info = platformInfo.${system};

          # Fetch and prepare the Droids CLI binary
          droid-binary = pkgs.stdenv.mkDerivation {
            name = "droid-binary";
            src = pkgs.fetchurl {
              url = "https://downloads.factory.ai/factory-cli/releases/${version}/${info.platform}/${info.arch}/droid";
              sha256 = info.droidSha256;
            };

            dontUnpack = true;
            dontBuild = true;

            installPhase = ''
              mkdir -p $out/bin
              cp $src $out/bin/droid
              chmod +x $out/bin/droid
            '';
          };

          # Fetch and prepare ripgrep binary (Droids dependency)
          rg-binary = pkgs.stdenv.mkDerivation {
            name = "rg-binary";
            src = pkgs.fetchurl {
              url = "https://downloads.factory.ai/ripgrep/${info.platform}/${info.arch}/rg";
              sha256 = info.rgSha256;
            };

            dontUnpack = true;
            dontBuild = true;

            installPhase = ''
              mkdir -p $out/bin
              cp $src $out/bin/rg
              chmod +x $out/bin/rg
            '';
          };

          # Create a wrapper for the droid command with binaries included
          droid-wrapper = pkgs.buildFHSEnv {
            name = "droid";

            targetPkgs =
              pkgs: with pkgs; [
                # Core dependencies
                curl
                git
                gnused
                gawk
                coreutils
                findutils

                # For browser opening (Linux requirement)
                xdg-utils

                # Common development tools that might be needed
                nodejs
                python3
                gcc
              ];

            runScript = pkgs.writeShellScript "droid-run" ''
              # Set up Factory environment
              export FACTORY_DIR="$HOME/.factory"
              mkdir -p "$FACTORY_DIR/bin"

              # Ensure ripgrep is available in Factory's expected location
              if [ ! -f "$FACTORY_DIR/bin/rg" ]; then
                cp -f ${rg-binary}/bin/rg "$FACTORY_DIR/bin/rg"
                chmod +x "$FACTORY_DIR/bin/rg"
              fi

              # Run the droid binary from the FHS environment
              exec ${droid-binary}/bin/droid "$@"
            '';

            meta = with pkgs.lib; {
              description = "FactoryAI Droids - AI Coding Agents CLI";
              homepage = "https://factory.ai";
              license = licenses.unfree;
              platforms = [
                "x86_64-linux"
                "aarch64-linux"
              ];
            };
          };

        in
        {
          default = droid-wrapper;
          droids = droid-wrapper;
        }
      );

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/droid";
        };
      });
    };
}

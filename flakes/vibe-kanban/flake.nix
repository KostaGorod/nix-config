{
  description = "Vibe Kanban - AI Coding Agent Orchestration Tool";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          version = "0.0.143";
          binaryTag = "v0.0.143-20251229180119";
          baseUrl = "https://npm-cdn.vibekanban.com/binaries/${binaryTag}";

          # Map Nix system to vibe-kanban platform and hashes
          platformInfo = {
            "x86_64-linux" = {
              platform = "linux-x64";
              sha256 = "sha256-+EHiIQIWYI7wB4KWur5NePaeGBBBLqmon135VxKNVWk=";
            };
            "aarch64-linux" = {
              platform = "linux-arm64";
              sha256 = "sha256-32yaAGCFGfWOSKsLgHQgVXly7wY1UONY651ATSIzp+s=";
            };
          };

          info = platformInfo.${system};

          # Fetch and extract the vibe-kanban binary
          vibe-kanban-binary = pkgs.stdenv.mkDerivation {
            name = "vibe-kanban-binary-${version}";

            src = pkgs.fetchurl {
              url = "${baseUrl}/${info.platform}/vibe-kanban.zip";
              sha256 = info.sha256;
            };

            nativeBuildInputs = [ pkgs.unzip ];

            dontUnpack = true;
            dontBuild = true;

            installPhase = ''
              mkdir -p $out/bin
              unzip $src -d $out/bin
              chmod +x $out/bin/vibe-kanban
            '';
          };

          # Create FHS wrapper for compatibility
          vibe-kanban-wrapper = pkgs.buildFHSEnv {
            name = "vibe-kanban";

            targetPkgs = pkgs: with pkgs; [
              # Core dependencies
              curl
              git
              gnused
              gawk
              coreutils
              findutils

              # For browser opening
              xdg-utils

              # Common development tools
              nodejs
              python3
              gcc
            ];

            runScript = pkgs.writeShellScript "vibe-kanban-run" ''
              exec ${vibe-kanban-binary}/bin/vibe-kanban "$@"
            '';

            meta = with pkgs.lib; {
              description = "Vibe Kanban - Visual project management for AI coding agents";
              homepage = "https://vibekanban.com";
              license = licenses.asl20;
              platforms = [ "x86_64-linux" "aarch64-linux" ];
              mainProgram = "vibe-kanban";
            };
          };

        in
        {
          default = vibe-kanban-wrapper;
          vibe-kanban = vibe-kanban-wrapper;
        }
      );

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/vibe-kanban";
        };
      });
    };
}

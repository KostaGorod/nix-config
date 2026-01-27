{
  description = "Vibe Kanban - AI Coding Agent Orchestration Tool";

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

      mkPackage =
        pkgs: system:
        let
          info = platformInfo.${system};

          vibe-kanban-binary = pkgs.stdenv.mkDerivation {
            name = "vibe-kanban-binary-${version}";

            src = pkgs.fetchurl {
              url = "${baseUrl}/${info.platform}/vibe-kanban.zip";
              inherit (info) sha256;
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
        in
        pkgs.buildFHSEnv {
          name = "vibe-kanban";

          targetPkgs =
            pkgs: with pkgs; [
              curl
              git
              gnused
              gawk
              coreutils
              findutils
              xdg-utils
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
            platforms = [
              "x86_64-linux"
              "aarch64-linux"
            ];
            mainProgram = "vibe-kanban";
          };
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in
        {
          default = mkPackage pkgs system;
          vibe-kanban = mkPackage pkgs system;
        }
      );

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/vibe-kanban";
        };
      });

      # NixOS module for systemd service
      nixosModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.services.vibe-kanban;
          pkg = mkPackage pkgs pkgs.stdenv.hostPlatform.system;
        in
        {
          options.services.vibe-kanban = {
            enable = lib.mkEnableOption "Vibe Kanban - AI coding agent orchestration";

            package = lib.mkOption {
              type = lib.types.package;
              default = pkg;
              description = "The Vibe Kanban package to use";
            };

            port = lib.mkOption {
              type = lib.types.port;
              default = 8080;
              description = "Port to bind the Vibe Kanban web server";
            };

            host = lib.mkOption {
              type = lib.types.str;
              default = "127.0.0.1";
              description = "Host address to bind (use 0.0.0.0 for all interfaces)";
            };

            openFirewall = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Whether to open the firewall for Vibe Kanban";
            };

            user = lib.mkOption {
              type = lib.types.str;
              default = "kosta";
              description = "User to run Vibe Kanban as";
            };

            dataDir = lib.mkOption {
              type = lib.types.str;
              default = "/home/${cfg.user}/.vibe-kanban";
              description = "Directory for Vibe Kanban data";
            };
          };

          config = lib.mkIf cfg.enable {
            systemd.services.vibe-kanban = {
              description = "Vibe Kanban - AI Coding Agent Orchestration";
              wantedBy = [ "multi-user.target" ];
              after = [ "network.target" ];

              environment = {
                PORT = toString cfg.port;
                HOST = cfg.host;
                HOME = "/home/${cfg.user}";
              };

              serviceConfig = {
                Type = "simple";
                User = cfg.user;
                ExecStart = "${cfg.package}/bin/vibe-kanban";
                Restart = "on-failure";
                RestartSec = "5s";

                NoNewPrivileges = true;
                ProtectSystem = "strict";
                ProtectHome = false;
                ReadWritePaths = [
                  cfg.dataDir
                  "/home/${cfg.user}/.vibe-kanban"
                  "/home/${cfg.user}/.config/vibe-kanban"
                  "/home/${cfg.user}/.local/share/vibe-kanban"
                ];
                WorkingDirectory = cfg.dataDir;
                PrivateTmp = true;
              };
            };

            systemd.tmpfiles.rules = [
              "d ${cfg.dataDir} 0755 ${cfg.user} users -"
              "d /home/${cfg.user}/.vibe-kanban 0755 ${cfg.user} users -"
              "d /home/${cfg.user}/.config/vibe-kanban 0755 ${cfg.user} users -"
              "d /home/${cfg.user}/.local/share/vibe-kanban 0755 ${cfg.user} users -"
            ];

            networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

            environment.systemPackages = [ cfg.package ];
          };
        };
    };
}

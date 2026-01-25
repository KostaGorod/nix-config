{
  description = "KostaGorod's NixOS configuration";

  inputs = {
    # Core
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Flake infrastructure
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hardware
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Browsers
    zen-browser.url = "github:0xc000022070/zen-browser-flake";

    # AI Coding Agents
    nix-ai-tools = {
      url = "github:numtide/nix-ai-tools";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # Local flakes
    antigravity-fhs.url = "path:flakes/antigravity-fhs";
    abacusai-fhs.url = "path:flakes/abacusai-fhs";
    vibe-kanban.url = "path:flakes/vibe-kanban";
    cosmic-unstable.url = "path:flakes/cosmic-unstable";

    # Tools
    ultimate-bug-scanner.url = "github:Dicklesworthstone/ultimate_bug_scanner";
  };

  outputs =
    inputs@{ flake-parts, nixpkgs, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = [
        inputs.treefmt-nix.flakeModule
      ];

      perSystem =
        { config, pkgs, ... }:
        let
          testLib = import ./lib/tests.nix {
            inherit pkgs;
            inherit (pkgs) lib;
          };
          testArgs = {
            inherit config pkgs inputs;
            tests = testLib;
            inherit (pkgs) lib;
          };
        in
        {
          treefmt = {
            projectRootFile = "flake.nix";
            settings.excludes = [ "flakes/**" ];
            programs = {
              nixfmt.enable = true;
              deadnix.enable = true;
              statix.enable = true;
            };
          };

          # CI checks - auto-discover and run localized tests
          checks = testLib.mkChecks testArgs [
            ./modules/nixos/services.nix.test.nix
            ./modules/nixos/tailscale.nix.test.nix
            ./modules/nixos/desktop.nix.test.nix
            ./modules/nixos/utils.nix.test.nix
            ./hosts/rocinante/default.nix.test.nix
            ./hosts/rocinante/profile-check.test.nix
            ./users/kosta/packages.nix.test.nix
          ];
        };

      flake = {
        nixosConfigurations.rocinante = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/rocinante
            ./hosts/rocinante/disko-config.nix
            inputs.disko.nixosModules.disko
            ./profiles/workstation.nix
            ./de/plasma6.nix
            inputs.cosmic-unstable.nixosModules.default
            ./modules/nixos/utils.nix
            ./modules/spotify.nix
            ./modules/moonlight-qt.nix
            inputs.vibe-kanban.nixosModules.default
            {
              services.vibe-kanban = {
                enable = true;
                port = 8080;
              };
            }
            inputs.home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                backupFileExtension = "backup";
                extraSpecialArgs = { inherit inputs; };
                users.kosta = import ./users/kosta;
              };
            }
          ];
        };
      };
    };
}

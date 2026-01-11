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

      perSystem = _: {
        # Formatter configuration
        treefmt = {
          projectRootFile = "flake.nix";
          # Exclude nested flakes (they have their own formatting rules)
          settings.excludes = [ "flakes/**" ];
          programs = {
            nixfmt.enable = true;
            deadnix.enable = true;
            statix.enable = true;
          };
        };
      };

      flake = {
        # NixOS configurations
        nixosConfigurations.rocinante = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            # Host-specific configuration
            ./hosts/rocinante
            ./hosts/rocinante/disko-config.nix

            # Disko for declarative disk management
            inputs.disko.nixosModules.disko

            # Workstation profile (services, desktop, AI tools)
            ./profiles/workstation.nix

            # Desktop environments
            ./de/plasma6.nix
            inputs.cosmic-unstable.nixosModules.default

            # Additional modules
            ./modules/nixos/utils.nix
            ./modules/spotify.nix
            ./modules/moonlight-qt.nix

            # Vibe Kanban service
            inputs.vibe-kanban.nixosModules.default
            {
              services.vibe-kanban = {
                enable = true;
                port = 8080;
              };
            }

            # Home Manager integration
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

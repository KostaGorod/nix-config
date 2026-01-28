{
  description = "KostaGorod's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser.url = "github:0xc000022070/zen-browser-flake";

    nix-ai-tools = {
      url = "github:numtide/nix-ai-tools";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    antigravity = {
      url = "github:jacopone/antigravity-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    abacusai-fhs = {
      url = "github:KostaGorod/nix-config?dir=flakes/abacusai-fhs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    vibe-kanban = {
      url = "github:KostaGorod/nix-config?dir=flakes/vibe-kanban";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # cosmic-unstable = {
    #   url = "github:lilyinstarlight/nixos-cosmic";
    #   inputs.nixpkgs.follows = "nixpkgs-unstable";
    # };

    ultimate-bug-scanner.url = "github:Dicklesworthstone/ultimate_bug_scanner";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      flake-parts,
      nixpkgs,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = [
        inputs.treefmt-nix.flakeModule
      ];

      perSystem = _: {
        treefmt = {
          projectRootFile = "flake.nix";
          settings.excludes = [ "flakes/**" ];
          programs = {
            nixfmt.enable = true;
            deadnix.enable = true;
            statix.enable = true;
          };
        };

        checks = {
          # Only check the actual host build for now
          rocinante-toplevel = self.nixosConfigurations.rocinante.config.system.build.toplevel;
        };
      };

      flake = {
        nixosConfigurations.rocinante = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/rocinante
            ./hosts/rocinante/disko-config.nix
            inputs.disko.nixosModules.disko
            inputs.agenix.nixosModules.default
            ./modules/nixos/secrets.nix
            ./profiles/workstation.nix
            ./de/plasma6.nix
            # inputs.cosmic-unstable.nixosModules.default
            ./de/cosmic.nix
            ./modules/nixos/utils.nix
            ./modules/nixos/cliphist.nix
            ./modules/nixos/spotify.nix
            ./modules/nixos/moonlight-qt.nix
            ./modules/nixos/tlp-power-profiles-bridge.nix
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

        nixosConfigurations.gpu-node-1 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/gpu-node-1/configuration.nix
            inputs.disko.nixosModules.disko
            inputs.agenix.nixosModules.default
            ./modules/nixos/secrets.nix
            ./hosts/gpu-node-1/disko-config.nix
            ./hosts/gpu-node-1/hardware-configuration.nix
          ];
        };
      };
    };
}

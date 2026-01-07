{
  description = "KostaGorod's Nixos configuration";
  inputs = {
    # core
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11"; # NOTE: Replace "nixos-24.05" with that which is in system.stateVersion of configuration.nix. You can also use later versions.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # hardware
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home-manager
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Other
    # nix-ld = { # Run unpatched dynamic binaries on NixOS.
    #   url = "github:Mic92/nix-ld";
    #   inputs.nixpkgs.follows = "nixpkgs-unstable";
    # };
    zen-browser.url = "github:0xc000022070/zen-browser-flake";

    # Unified AI Coding Agents from numtide/nix-ai-tools
    nix-ai-tools = {
      url = "github:numtide/nix-ai-tools";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # Warp Terminal with FHS environment
    warp-fhs = {
      url = "path:flakes/warp-fhs";
      # Don't follow our nixpkgs to avoid unnecessary downloads
    };

    # Antigravity IDE (Google's AI-powered development environment)
    # Local wrapper around jacopone/antigravity-nix for easy updates
    antigravity-fhs = {
      url = "path:flakes/antigravity-fhs";
      # Don't follow our nixpkgs to avoid unnecessary downloads
      # The antigravity flake manages its own nixpkgs dependency
    };

    # AbacusAI DeepAgent Desktop and CLI
    abacusai-fhs = {
      url = "path:flakes/abacusai-fhs";
    };

    # Vibe Kanban - AI coding agent orchestration tool
    vibe-kanban = {
      url = "path:flakes/vibe-kanban";
    };

    # Ultimate Bug Scanner - Industrial-grade static analysis
    ultimate-bug-scanner = {
      url = "github:Dicklesworthstone/ultimate_bug_scanner";
    };

    # mikrotikDevEnv = {
    #   url = "path:environments/mikrotik";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };
  outputs = inputs@{ self, nixpkgs, nixpkgs-unstable, nixos-hardware, home-manager, disko, zen-browser, nix-ai-tools, warp-fhs, antigravity-fhs, abacusai-fhs, vibe-kanban, ultimate-bug-scanner, ... }:
  # let

  # in
  {
    nixConfig = {
      nix.settings.experimental-features = [ "nix-command" "flakes" ]; # enable flakes
    };

    nixosConfigurations.rocinante = nixpkgs.lib.nixosSystem {
      # inherit system; # inherited it from 'let' block
      specialArgs = { inherit inputs; }; # pass additional args to modules ( accesible via declared { config, pkgs, pkgs-stable, ...} at the top of the module.nix files)
      modules = [
        ./hosts/rocinante/configuration.nix
        # nixos-hardware.nixosModules.lenovo-thinkpad-x1-9th-gen
        inputs.disko.nixosModules.disko
        ./hosts/rocinante/disko-config.nix

        # nix-ld.nixosModules.nix-ld
        # { programs.nix-ld.dev.enable = true; }

        # make home-manager as a module of nixos
        # so that home-manager configuration will be deployed automatically when executing `nixos-rebuild switch`
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true; # makes home-manager follow nixos's pkgs value
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup"; # Backup existing files that conflict with home-manager
          home-manager.users.kosta = import ./home-manager/home.nix;

          # pass arguments to home.nix
          home-manager.extraSpecialArgs = { inherit inputs; };
        }

        # others
        ./de/plasma6.nix
        ./modules/utils.nix
        ./modules/editors.nix
        ./modules/spotify.nix
        ./modules/moonlight-qt.nix
        ./modules/droids.nix
        ./modules/abacusai.nix

        # Vibe Kanban service (module from flake)
        vibe-kanban.nixosModules.default
      ];
    };
  };
}

{
  description = "KostaGorod's Nixos configuration";
  inputs = {
    # core
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.05"; # NOTE: Replace "nixos-24.05" with that which is in system.stateVersion of configuration.nix. You can also use later versions.

    # hardware
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home-manager
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Other
    nix-ld = { # Run unpatched dynamic binaries on NixOS.
      url = "github:Mic92/nix-ld";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen-browser.url = "github:0xc000022070/zen-browser-flake";

    # custom flakes fixing gpu issue
    wezterm = {
      url = "github:wez/wezterm/main?dir=nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # mikrotikDevEnv = {
    #   url = "path:environments/mikrotik";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };
  # outputs = inputs@{ self, nixpkgs, nixos-hardware, disko, home-manager, ... }: {
  outputs = inputs@{ self, nixpkgs, nixpkgs-stable, nix-ld , nixos-hardware, home-manager, disko, zen-browser, ... }:
  let
    system = "x86_64-linux";
    # lib = nixpkgs.lib;
    pkgs-stable = nixpkgs-stable.legacyPackages.${system}; #https://discourse.nixos.org/t/mixing-stable-and-unstable-packages-on-flake-based-nixos-system/50351/2
  in
  {
    nixConfig = {
      nix.settings.experimental-features = [ "nix-command" "flakes" ]; # enable flakes
    };

    nixosConfigurations.rocinante = nixpkgs.lib.nixosSystem {
      inherit system; # inherited it from 'let' block
      specialArgs = { inherit pkgs-stable inputs; }; # pass additional args to modules ( accesible via declared { config, pkgs, pkgs-stable, ...} at the top of the module.nix files)
      modules = [
        ./hosts/rocinante/configuration.nix
        # nixos-hardware.nixosModules.lenovo-thinkpad-x1-9th-gen
        inputs.disko.nixosModules.disko
        ./hosts/rocinante/disko-config.nix

        nix-ld.nixosModules.nix-ld
        { programs.nix-ld.dev.enable = true; }

        # make home-manager as a module of nixos
        # so that home-manager configuration will be deployed automatically when executing `nixos-rebuild switch`
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true; # makes home-manager follow nixos's pkgs value
          home-manager.useUserPackages = true;
          home-manager.users.kosta = import ./home-manager/home.nix;

          # pass arguments to home.nix
          home-manager.extraSpecialArgs = { inherit inputs system; };
        }

        # others
        ./de/plasma6.nix
        ./modules/utils.nix
        ./modules/editors.nix
        ./modules/spotify.nix

      ];
    };
  };
}

{
  description = "COSMIC Desktop Environment from nixpkgs-unstable (1.0.1+ with network applet fix)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    {
      # NixOS module that provides COSMIC from unstable
      nixosModules.default =
        { lib, pkgs, ... }:
        let
          pkgs-unstable = import nixpkgs {
            inherit (pkgs.stdenv.hostPlatform) system;
            config.allowUnfree = true;
          };

          # All COSMIC packages to overlay from unstable
          cosmicPackages = [
            "cosmic-applets"
            "cosmic-applibrary"
            "cosmic-bg"
            "cosmic-comp"
            "cosmic-edit"
            "cosmic-files"
            "cosmic-greeter"
            "cosmic-icons"
            "cosmic-idle"
            "cosmic-launcher"
            "cosmic-notifications"
            "cosmic-osd"
            "cosmic-panel"
            "cosmic-randr"
            "cosmic-screenshot"
            "cosmic-session"
            "cosmic-settings"
            "cosmic-settings-daemon"
            "cosmic-store"
            "cosmic-term"
            "cosmic-workspaces-epoch"
            "xdg-desktop-portal-cosmic"
          ];

          # Create overlay from package list
          cosmicOverlay =
            _final: prev: lib.genAttrs cosmicPackages (name: pkgs-unstable.${name} or (prev.${name} or null));
        in
        {
          nixpkgs.overlays = [ cosmicOverlay ];

          # Enable COSMIC desktop environment
          services.desktopManager.cosmic.enable = true;

          # System76 scheduler for improved COSMIC performance
          services.system76-scheduler.enable = true;
        };
    };
}

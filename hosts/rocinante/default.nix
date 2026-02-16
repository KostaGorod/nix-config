# Rocinante host configuration
# System-level settings only - no user packages here
{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
let
  pkgs-unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };
in
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/fingerprint.nix
    ../../modules/nixos/yubikey.nix
    ./configuration.nix
  ];

  # Fix upstream systemd ordering cycle:
  # tlp.service ships with `After=multi-user.target` while also being `WantedBy=multi-user.target`.
  # When combined with tlp-power-profiles-bridge (WantedBy=multi-user.target, After=tlp.service),
  # systemd can hit an unbreakable cycle while (re)starting multi-user.target.
  nixpkgs.overlays = [
    (_final: prev: {
      tlp = prev.tlp.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          if [ -e "$out/lib/systemd/system/tlp.service" ]; then
            substituteInPlace "$out/lib/systemd/system/tlp.service" \
              --replace "After=multi-user.target NetworkManager.service" "After=NetworkManager.service"
          fi
        '';
      });
    })
  ];

  # Boot menu label: use git commit info or "dirty" if uncommitted
  system.nixos.label =
    let
      # Get git info at build time
      gitRev = inputs.self.shortRev or "dirty";
      gitDesc = inputs.self.lastModifiedDate or "unknown";
    in
    "${gitRev}-${gitDesc}";

  # Nix settings
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
    };
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;
  };
  nixpkgs.config.allowUnfree = lib.mkForce true;
  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "claude-code"
      "droid"
    ];

  # Boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Networking
  networking.hostName = "rocinante";
  networking.networkmanager = {
    enable = true;
    dns = "none"; # Use standalone dnsmasq.service from tailscale.nix module
    plugins = [ pkgs.networkmanager-openvpn ];
  };
  networking.modemmanager.fccUnlockScripts = [
    {
      id = "1eac:1001";
      path = "${pkgs.modemmanager}/share/ModemManager/fcc-unlock.available.d/1eac:1001";
    }
  ];
  networking.timeServers = [ "timeserver.iix.net.il" ];
  # firewall configured in configuration.nix

  # Virtualization
  virtualisation.docker.enable = true;
  virtualisation.docker.package = pkgs.docker_28;

  # Hardware
  hardware.bluetooth.enable = true;
  hardware.fingerprint.enable = true; # Fingerprint authentication for sudo/polkit/login
  hardware.yubikey.enable = true; # FIDO2 support (libfido2 for SSH *-sk keys)
  hardware.logitech.wireless.enable = true;
  hardware.logitech.wireless.enableGraphical = true;
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      libva-vdpau-driver
    ];
  };

  # Locale
  time.timeZone = "Asia/Jerusalem";
  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS = "en_US.UTF-8";
      LC_IDENTIFICATION = "en_US.UTF-8";
      LC_MEASUREMENT = "en_US.UTF-8";
      LC_MONETARY = "en_US.UTF-8";
      LC_NAME = "en_US.UTF-8";
      LC_NUMERIC = "en_US.UTF-8";
      LC_PAPER = "en_US.UTF-8";
      LC_TELEPHONE = "en_US.UTF-8";
      LC_TIME = "en_IL";
    };
  };

  # System settings
  systemd.targets.hibernate.enable = false;
  programs.fish.enable = true;
  environment.etc.current-nixos-config.source = ./.;
  environment.variables.EDITOR = "hx";
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
    # Fix cross-device link error for Claude Code plugin installation
    # Use ~/.claude/tmp instead of /tmp (which may be on tmpfs)
    TMPDIR = "$HOME/.claude/tmp";
  };

  # Security
  security.rtkit.enable = true;
  security.auditd.enable = true;
  security.audit.enable = true;

  # Programs (system-level)
  programs.adb.enable = true;
  programs.steam.enable = true;
  programs.direnv = {
    enable = true;
    package = pkgs-unstable.direnv;
    nix-direnv.enable = true;
  };

  # User account defined in configuration.nix

  # Minimal system packages (emergency/system-wide tools only)
  environment.systemPackages = with pkgs; [
    # Emergency editors
    vim
    helix

    # Core system tools
    bash
    coreutils
    wget
    openssl
    gettext

    # DevOps (system-level)
    devenv
    kind
    nix-update

    # Laptop specific
    libqmi

    # Ultimate Bug Scanner
    inputs.ultimate-bug-scanner.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  system.stateVersion = "24.05";
}

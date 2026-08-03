# Rocinante services, programs, and host-specific settings
# Hardware, boot, networking, locale, and Nix settings are in system.nix.
# AI tools are enabled by the workstation program contribution.
_: {
  nixos.configurations.rocinante.module =
    {
      lib,
      pkgs,
      ...
    }:
    {

      services.tailscale-mesh.enable = true;

      # Binary caches (cosmic, numtide); base Nix settings are in system.nix.
      nix.settings = {
        trusted-users = [
          "root"
          "kosta"
        ];
        substituters = [
          "https://cache.nixos.org/"
          "https://cosmic.cachix.org/"
          "https://cache.numtide.com"
        ];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "cosmic.cachix.org-1:Dya9IyXD4xdBehWjX818gw+s7maCeSJ8844iQ80x1M0="
          "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
        ];
      };

      # Hardware, locale, boot, and networking are defined in system.nix.

      # Enable CUPS - host-specific drivers, localhost only
      services.printing = {
        drivers = [
          pkgs.hplip
          pkgs.pantum-driver
        ];
        listenAddresses = [ "localhost:631" ];
        allowFrom = [ "localhost" ];
        defaultShared = false;
      };
      services.avahi = {
        # Printers discovery (Apple streaming disabled)
        enable = lib.mkForce false;
        nssmdns4 = false;
        openFirewall = false;
        # Disable Apple streaming/AirPlay features
        publish = {
          enable = false; # Don't advertise this machine
          userServices = false; # Don't publish user services (AirPlay receivers)
          addresses = false; # Don't publish addresses
          hinfo = false; # Don't publish hardware info
          workstation = false; # Don't publish workstation service
        };
        reflector = false; # Don't reflect mDNS (used by AirPlay across subnets)
      };

      # Enable SSH with TPM PKCS#11 for hardware-backed SSH keys
      security.ssh-tpm = {
        enable = true;
        users = [ "kosta" ]; # Grant TPM access to kosta
      };

      # Power Management
      services.power-profiles-daemon.enable = false; # doesn't work with TLP.
      services.tlp-power-profiles-bridge.enable = true; # COSMIC power UI via TLP
      services.tlp = {
        enable = true;
        settings = {
          CPU_SCALING_GOVERNOR_ON_AC = "performance";
          CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

          CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
          CPU_ENERGY_PERF_POLICY_ON_AC = "performance";

          PLATFORM_PROFILE_ON_AC = "performance";
          PLATFORM_PROFILE_ON_BAT = "low-power";

          CPU_MIN_PERF_ON_AC = 0;
          CPU_MAX_PERF_ON_AC = 100;
          CPU_MIN_PERF_ON_BAT = 0;
          CPU_MAX_PERF_ON_BAT = 20;

          #Optional helps save long term battery health
          START_CHARGE_THRESH_BAT0 = 40; # 40 and bellow it starts to charge
          STOP_CHARGE_THRESH_BAT0 = 80; # 80 and above it stops charging

          RUNTIME_PM_ON_AC = "on"; # Keep devices active (no suspend) on AC to prevent touchpad delay
          RUNTIME_PM_ON_BAT = "auto";

          # USB_AUTOSUSPEND = 0;
          USB_DENYLIST = "0bda:8153"; # 17ef:*";

          MEM_SLEEP_ON_AC = "deep"; # "s2idle";
          MEM_SLEEP_ON_BAT = "deep";

          RUNTIME_PM_DRIVER_DENYLIST = "mei_me nouveau xhci_hcd"; # mhi_pci_generic";
          # Driver denylist   = mei_me nouveau radeon #original
        };
      };

      users.defaultUserShell = pkgs.fish;
      programs.kdeconnect.enable = true;

      # Droids, Claude Code, OpenCode, and Bitwarden are enabled by the workstation module.

      # User account; packages are contributed by modules/users/kosta/packages.nix.
      users.users.kosta = {
        isNormalUser = true;
        extraGroups = [
          "wheel"
          "networkmanager"
          "docker"
          "adbusers"
          "seat"
        ];
        shell = pkgs.bash;
      };

      # Fonts, desktop utilities, and Antigravity are contributed by modules/desktop/packages.nix.

      # Host-specific system packages (not covered by modules)
      environment.systemPackages = with pkgs; [
        nixd # Nix language server
        teamviewer
      ];
      services.teamviewer.enable = true;

      # Stateful default-deny firewall; Tailscale gets its own allow rules.
      networking.firewall = {
        enable = true;

        extraCommands = ''
          iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
          iptables -A INPUT -i tailscale0 -p icmp -j ACCEPT
        '';

        extraStopCommands = ''
          iptables -D INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
          iptables -D INPUT -i tailscale0 -p icmp -j ACCEPT 2>/dev/null || true
        '';
      };

      # Auto-upgrade (weekly, no auto-reboot)
      system.autoUpgrade = {
        enable = true;
        allowReboot = false;
        dates = "weekly";
      };

    };
}

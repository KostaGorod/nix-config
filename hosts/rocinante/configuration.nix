# Rocinante services, programs, and host-specific settings
# Hardware, boot, networking, locale, nix settings — see default.nix
# AI tools (droids, claude-code, opencode, etc.) — see profiles/workstation.nix
{
  lib,
  pkgs,
  ...
}:
let
  gpu-node-tailscale-ip = "100.102.123.22";
in
{

  imports = [
    ../../modules/nixos/tailscale.nix
    ../../modules/nixos/nix-ld.nix
    ../../modules/nixos/mem0.nix
    ../../modules/nixos/ssh-tpm-pkcs11.nix
  ];

  # Binary caches (cosmic, numtide) — base nix settings in default.nix
  nix.settings = {
    trusted-users = [ "root" "kosta" ];
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

  # Hardware, locale, boot, networking — defined in default.nix

  services.fwupd.enable = true;

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

  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa = {
      enable = true;
      support32Bit = true;
    };
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

  # droids, claude-code, opencode, abacusai, bitwarden enabled via profiles/workstation.nix

  # Enable Mem0 AI memory layer for persistent agent memory (self-hosted)
  programs.mem0 = {
    enable = true;
    selfHosted = true;
    userId = "kosta";
  };

  # Mem0 MCP server as systemd service (SSE transport)
  services.mem0 = {
    enable = false;
    port = 8050;
    userId = "kosta";
    # host = "0.0.0.0";  # uncomment to expose to network
    # openFirewall = true;

    # VoyageAI embeddings (voyage-4-lite)
    embedder = {
      provider = "voyageai";
      model = "voyage-4-lite";
      apiKeyFile = "/run/secrets/voyage-api-key"; # Create this file with your API key
    };

    # LLM for memory extraction (uses Anthropic)
    llm = {
      provider = "anthropic";
      model = "claude-sonnet-4-20250514";
      apiKeyFile = "/run/secrets/anthropic-api-key"; # Create this file with your API key
    };
  };

  # User account (packages managed via home-manager in users/kosta/packages.nix)
  users.users.kosta = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "docker"
      "adbusers"
    ];
    shell = pkgs.bash;
  };

  # Fonts, desktop utilities, antigravity — see modules/nixos/desktop.nix (via workstation profile)

  # Host-specific system packages (not covered by modules)
  environment.systemPackages = with pkgs; [
    nixd # Nix language server
    teamviewer
  ];
  services.teamviewer.enable = true;

  # Firewall enabled with strict default-deny policy
  # Tailscale in separate zone with granular access control
  networking.firewall = {
    enable = true;

    # Tailscale zone: Allow basic connectivity, but restrict specific ports
    extraCommands = ''
      # Allow established connections (stateful firewall)
      iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

      # Allow Tailscale ICMP (ping, network discovery)
      iptables -A INPUT -i tailscale0 -p icmp -j ACCEPT

      # Allow port 9898 only from specific IP (not entire Tailscale network)
      iptables -A INPUT -p tcp -s ${gpu-node-tailscale-ip} --dport 9898 -j ACCEPT

      # Allow other necessary Tailscale traffic (add as needed)
      # Examples:
      # iptables -A INPUT -i tailscale0 -p tcp --dport 22 -j ACCEPT  # SSH via Tailscale
      # iptables -A INPUT -i tailscale0 -p tcp --dport 443 -j ACCEPT  # HTTPS via Tailscale
    '';

    extraStopCommands = ''
      iptables -D INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
      iptables -D INPUT -i tailscale0 -p icmp -j ACCEPT 2>/dev/null || true
      iptables -D INPUT -p tcp -s ${gpu-node-tailscale-ip} --dport 9898 -j ACCEPT 2>/dev/null || true
    '';
  };

  # Auto-upgrade (weekly, no auto-reboot)
  system.autoUpgrade = {
    enable = true;
    allowReboot = false;
    dates = "weekly";
  };

}

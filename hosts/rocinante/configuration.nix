# Edit this configuration file to define what should be installed on
#
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

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

  # 1. Disable the networking modules from unstable
  # disabledModules = [
  #   "config/networking.nix"                          # core networking settings (hosts, interfaces, firewall, etc.)
  #   "services/networking/networkmanager.nix"         # NetworkManager service module
  #   # "services/networking/modemmanager.nix"
  #   # "services/networking/wpa_supplicant.nix"         # WPA supplicant (wireless) service module
  #   # ... add any other networking-related modules you want to take from stable ...
  # ];

  # 2. Import the networking modules from the stable nixpkgs
  imports = [
    # hardware-configuration.nix imported via default.nix
    ../../modules/nixos/tailscale.nix # Tailscale configuration module
    ../../modules/nixos/nix-ld.nix # nix-ld for dynamic binary support (uv, python venvs)
    ../../modules/nixos/opencode.nix # OpenCode AI coding agent
    ../../modules/nixos/claude-code.nix # Claude Code CLI
    ../../modules/nixos/mem0.nix # Mem0 AI memory layer
    # ../../modules/nixos/codex.nix # Numtide Codex AI assistant (temporarily disabled)
    ../../modules/nixos/bitwarden.nix # Bitwarden password manager (unstable)

    #"${pkgs-stable.path}/nixos/modules/config/networking.nix"
    #"${pkgs-stable.path}/nixos/modules/services/networking/networkmanager.nix"
    # "${pkgs-stable.path}/nixos/modules/services/networking/modemmanager.nix"
    # "${pkgs-stable.path}/nixos/modules/services/networking/wpa_supplicant.nix"
  ];

  nix.settings = {
    substituters = [
      "https://cache.nixos.org/"
      "https://cosmic.cachix.org/"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "cosmic.cachix.org-1:Dya9IyXD4xdBehWjX818gw+s7maCeSJ8844iQ80x1M0="
    ];
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };
  #nix.channel.enable = true; # not sure if needed at all
  nix = {
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

  };
  nixpkgs.config.allowUnfree = lib.mkForce true; # force allow unfree (if unfree is false by default)
  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "claude-code"
      "droid"
      # "codex" # temporarily disabled
    ];

  # Bootloader.
  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "rocinante"; # hostname.

  networking.networkmanager = {
    enable = true; # Easiest to use and most distros use this by default.
    dns = "none"; # Use standalone dnsmasq.service from tailscale.nix module
    plugins = [ pkgs.networkmanager-openvpn ]; # OpenVPN support in NetworkManager
  };
  # Unlock Integrated Modem
  networking.modemmanager.fccUnlockScripts = [
    {
      id = "1eac:1001";
      path = "${pkgs.modemmanager}/share/ModemManager/fcc-unlock.available.d/1eac:1001";
    }
  ];
  networking.timeServers = [ "timeserver.iix.net.il" ]; # Items in list seperated by space e.g.: [ "time.cloudflare.com" "time.example.com" ];

  # networking.dhcpcd.extraConfig = ''
  # interface enp*
  # metric 100

  # interface wlp0s20f3
  # metric 200

  # interface wwan*
  # metric 300

  # '';

  # fwupdmgr for firmwares updates
  services.fwupd.enable = true;

  # bluetooth
  hardware.bluetooth.enable = true;

  # Logitech unify & solaar (logitech control interface)
  hardware.logitech.wireless.enable = true;
  hardware.logitech.wireless.enableGraphical = true;

  # Locale
  time.timeZone = "Asia/Jerusalem";
  i18n = {
    defaultLocale = "en_US.UTF-8";

    # Add additional locales
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

    # Generate the locales you need

  };

  # S3 sleep is great enough
  systemd.targets.hibernate.enable = false;

  #copy current config into etc, this way I can restore config if current evaluation is broken, BEWARE it can contain secrets and such...
  # or just use git
  environment.etc.current-nixos-config.source = ./.; # https://logs.nix.samueldr.com/nixos/2018-06-25#1529934995-1529935276;

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

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

  # Enable sound.
  # hardware.pulseaudio.enable = true;
  # OR
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    # jack.enable = false;
    # wireplumber.enable = true;
    alsa = {
      enable = true;
      support32Bit = true;
    };
  };
  security.rtkit.enable = true; # realtime scheduling priority to user processes on demand https://mynixos.com/nixpkgs/option/security.rtkit.enable

  #enable audit #DISA-STIG
  security.auditd.enable = true;
  security.audit.enable = true;



  # Power Management
  services.power-profiles-daemon.enable = false; # doesn't work with TLP.
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

  # set user's default shell system-wide (for all users)
  users.defaultUserShell = pkgs.fish;

  programs.adb.enable = true;

  # Enable FactoryAI Droids IDE
  programs.droids.enable = true;

  # Enable Anthropic Claude Code CLI
  programs.claude-code.enable = true;

  # Enable Numtide Codex AI assistant (temporarily disabled)
  # programs.codex.enable = true;

  # Enable OpenCode AI coding agent
  programs.opencode.enable = true;

  # Enable Mem0 AI memory layer for persistent agent memory (self-hosted)
  programs.mem0 = {
    enable = true;
    selfHosted = true;
    userId = "kosta";
  };

  # Mem0 MCP server as systemd service (SSE transport)
  services.mem0 = {
    enable = true;
    port = 8050;
    userId = "kosta";
    # host = "0.0.0.0";  # uncomment to expose to network
    # openFirewall = true;

    # VoyageAI embeddings (voyage-4-lite)
    embedder = {
      provider = "voyageai";
      model = "voyage-4-lite";
      apiKeyFile = "/run/secrets/voyage-api-key";  # Create this file with your API key
    };

    # LLM for memory extraction (uses Anthropic)
    llm = {
      provider = "anthropic";
      model = "claude-sonnet-4-20250514";
      apiKeyFile = "/run/secrets/anthropic-api-key";  # Create this file with your API key
    };
  };

  # Enable Abacus.AI DeepAgent desktop client and CLI
  programs.abacusai.enable = true;

  # Enable Bitwarden password manager (from nixpkgs-unstable)
  programs.bitwarden.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.kosta = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "docker"
      "adbusers"
    ]; # Enable 'sudo' for the user. # Enable manage access to NetworkManager
    shell = pkgs.bash;
    packages = with pkgs; [
      # Antigravity IDE (Google AI-powered development environment)
      inputs.antigravity-fhs.packages.${pkgs.stdenv.hostPlatform.system}.default
      pkgs-unstable.uv
      # Warp terminal
      warp-terminal
      _1password-gui
      firefox
      kdePackages.kdeconnect-kde
      kdePackages.plasma-browser-integration
      pciutils
      remmina # rdp client
      onlyoffice-desktopeditors
      #
      # modified Vivaldi package for native wayland support, also fixes crash in plasma6
      # ((vivaldi.overrideAttrs (oldAttrs: {
      #   buildPhase = builtins.replaceStrings #add qt6 to patch
      #     ["for f in libGLESv2.so libqt5_shim.so ; do"]
      #     ["for f in libGLESv2.so libqt5_shim.so libqt6_shim.so ; do"]
      #     oldAttrs.buildPhase;
      # })).override {
      #   qt5 = pkgs.qt6; # use qt6
      #   commandLineArgs = [
      #     "--ozone-platform=wayland"
      #     "--disable-gpu-memory-buffer-video-frames" # stop spam for full gpu buffer, hotfix for chromium 126-130, hopefully fixed on 131: https://github.com/th-ch/youtube-music/pull/2519
      #     ];
      #   proprietaryCodecs = true; # Optional
      #   enableWidevine = true;    # Optional
      # })
      (vivaldi.override {
        commandLineArgs = [
          "--ozone-platform=wayland"
          "--disable-gpu-memory-buffer-video-frames" # stop spam for full gpu buffer, hotfix for chromium 126-130, hopefully fixed on 131: https://github.com/th-ch/youtube-music/pull/2519
        ];
        proprietaryCodecs = true; # Optional
        enableWidevine = true; # Optional
      })
      gitkraken
    ];
  };

  # Set the default editor to helix
  environment.variables.EDITOR = "hx";

  fonts.packages = with pkgs; [
    helvetica-neue-lt-std
    fragment-mono # Helvetica Monospace Coding Font
    aileron # Helvetica font in nine weights

  ];
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    # Antigravity IDE wrapper script and desktop entry
    (makeDesktopItem {
      name = "antigravity";
      desktopName = "Antigravity IDE";
      comment = "Google Antigravity AI-powered development environment";
      exec = "${
        inputs.antigravity-fhs.packages.${pkgs.stdenv.hostPlatform.system}.default
      }/bin/antigravity %U";
      icon = "code";
      terminal = false;
      type = "Application";
      categories = [
        "Development"
        "IDE"
      ];
    })
    (writeShellScriptBin "antigravity" ''
      exec ${
        inputs.antigravity-fhs.packages.${pkgs.stdenv.hostPlatform.system}.default
      }/bin/antigravity "$@"
    '')

    # Shells
    bash # Required by some applications like warp-terminal

    # Terminal Editors
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    helix

    # GUI
    numix-cursor-theme
    gnome-calculator
    # Virtual Keyboard
    maliit-keyboard
    maliit-framework

    # devops tools
    devenv
    kind
    nix-update # Tool for updating nix packages
    #
    sshuttle
    coreutils
    openssl
    gettext
    wget
    jqp
    jp
    httpie
    borgbackup
    easyeffects
    teamviewer
    # (zed-editor.fhsWithPackages (pkgs: [ pkgs.zlib ])) # zed missing zlib to work is expected https://github.com/xhyrom/zed-discord-presence/issues/12
    (python312.withPackages (
      ps: with ps; [
        ipython
        bpython
        #pandas
        requests
        #pyquery
        pyyaml
      ]
    ))
    # Install Vulkan tools (replaces opengl)
    # Test with vulkaninfo
    # https://www.reddit.com/r/NixOS/comments/ernur4/anyway_i_can_get_vulkan_installed/
    vulkan-tools

    # Laptop specific tools
    libqmi

    # Ultimate Bug Scanner - static analysis tool
    inputs.ultimate-bug-scanner.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
  services.teamviewer.enable = true;

  programs.steam = {
    enable = true;
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];

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
      iptables -A INPUT -p tcp -s 100.102.123.22 --dport 9898 -j ACCEPT

      # Allow other necessary Tailscale traffic (add as needed)
      # Examples:
      # iptables -A INPUT -i tailscale0 -p tcp --dport 22 -j ACCEPT  # SSH via Tailscale
      # iptables -A INPUT -i tailscale0 -p tcp --dport 443 -j ACCEPT  # HTTPS via Tailscale
    '';

    extraStopCommands = ''
      iptables -D INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
      iptables -D INPUT -i tailscale0 -p icmp -j ACCEPT 2>/dev/null || true
      iptables -D INPUT -p tcp -s 100.102.123.22 --dport 9898 -j ACCEPT 2>/dev/null || true
    '';
  };

  #works only on unstable (or 24.11)
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # VAAPI driver
      libva-vdpau-driver # VDPAU to VAAPI
      # libvdpau-va-gl # Wrapper for apps that doesnt support VDPAU (VAAPI to VDPAU)
    ];
  };
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
  };
  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "24.05"; # Did you read the comment?

  # Security hardening: Enable automatic security updates
  # Critical for CVE patching and vulnerability remediation
  system.autoUpgrade = {
    enable = true;
    allowReboot = false; # Manual reboot control required
    dates = "weekly"; # Check for updates weekly
  };

  # Optimising the NixOS store with automatic options. This will optimise the
  # store on every build which may slow down builds. The alternativ is to set
  # them on specific dates like this:
  # nix.optimise.automatic = true;
  # nix.optimise.dates = [ "03:45" ]; # Optional; allows customizing schedule
  nix.settings.auto-optimise-store = true;

}

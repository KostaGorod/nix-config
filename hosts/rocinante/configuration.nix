# Edit this configuration file to define what should be installed on
#
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ inputs, config, lib, pkgs, options, ... }:
let
  pkgs-unstable = import inputs.nixpkgs-unstable {
    system = pkgs.system;
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
    ./hardware-configuration.nix # Include the results of the hardware scan.
    ../../modules/tailscale.nix # Tailscale configuration module
    ../../modules/opencode.nix # OpenCode AI coding agent
    ../../modules/claude-code.nix # Claude Code CLI
    ../../modules/codex.nix # Numtide Codex AI assistant

    #"${pkgs-stable.path}/nixos/modules/config/networking.nix"
    #"${pkgs-stable.path}/nixos/modules/services/networking/networkmanager.nix"
    # "${pkgs-stable.path}/nixos/modules/services/networking/modemmanager.nix"
    # "${pkgs-stable.path}/nixos/modules/services/networking/wpa_supplicant.nix"
    ];


  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  #nix.channel.enable = true; # not sure if needed at all
  nix = {
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

  };
  nixpkgs.config.allowUnfree = lib.mkForce true; # force allow unfree (if unfree is false by default)
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "claude-code"
    "droid"
    "codex"
  ];

  # Bootloader.
  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "rocinante"; # hostname.

  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.
  # Unlock Integrated Modem
  networking.modemmanager.fccUnlockScripts = [ {id = "1eac:1001"; path = "${pkgs.modemmanager}/share/ModemManager/fcc-unlock.available.d/1eac:1001";} ];
  networking.timeServers = [ "timeserver.iix.net.il" ]; # Items in list seperated by space e.g.: [ "time.cloudflare.com" "time.example.com" ];

  # TODO: set [main] dns=dnsmasq (instead of internal)
  # networking.dhcpcd.extraConfig = ''
  # interface enp*
  # metric 100

  # interface wlp0s20f3
  # metric 200

  # interface wwan*
  # metric 300

  # '';

  # Virtualization
  virtualisation.docker.enable = true;
  virtualisation.docker.package = pkgs.docker_28;


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
  environment.etc.current-nixos-config.source = ./.; #https://logs.nix.samueldr.com/nixos/2018-06-25#1529934995-1529935276;


  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";


  # Enable CUPS to print documents.
  services.printing = {
    enable = true;
    drivers = [
      pkgs.hplip
      pkgs.pantum-driver
    ];
    # Enable network printer sharing
    listenAddresses = [ "*:631" ]; # Listen on all interfaces
    allowFrom = [ "all" ]; # Allow access from all hosts
    browsing = true; # Enable printer browsing
    defaultShared = true; # Share all printers by default
  };
  services.avahi = { # Printers & AirPlay AutoDiscovery
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
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

services.locate = {
enable = true;
#localuser = null; # use root, idk why its called null here.
package = pkgs.plocate; # default is locate.
interval = "hourly"; # possible with plocate because it's fast (because incremental)
};

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

      RUNTIME_PM_ON_AC = "auto" ; # Enabling runtime power management for PCI(e) bus devices while on AC may improve power saving on some laptops.
      RUNTIME_PM_ON_BAT= "auto" ;

      # USB_AUTOSUSPEND = 0;
      USB_DENYLIST = "0bda:8153"; # 17ef:*";

      MEM_SLEEP_ON_AC = "deep"; #"s2idle";
      MEM_SLEEP_ON_BAT = "deep";

      RUNTIME_PM_DRIVER_DENYLIST = "mei_me nouveau xhci_hcd"; #  mhi_pci_generic";
      # Driver denylist   = mei_me nouveau radeon #original
      };
};

  # set user's default shell system-wide (for all users)
  users.defaultUserShell = pkgs.bash;

  programs.adb.enable = true;

  # Enable FactoryAI Droids IDE
  programs.droids.enable = true;

  # Enable Anthropic Claude Code CLI
  programs.claude-code.enable = true;

  # Enable Numtide Codex AI assistant
  programs.codex.enable = true;

  # Enable OpenCode AI coding agent
  programs.opencode.enable = true;

  # users.users.kosta.extraGroups = lib.mkAfter ["adbusers"];
  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.kosta = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" "adbusers" ]; # Enable 'sudo' for the user. # Enable manage access to NetworkManager
    shell = pkgs.nushell;
    packages = with pkgs; [
      pkgs-unstable.uv
      # Warp terminal with FHS environment for full system access
      inputs.warp-fhs.packages.${pkgs.system}.default
      _1password-gui
      firefox
      kdePackages.kdeconnect-kde
      kdePackages.plasma-browser-integration
      pciutils
      remmina #rdp client
      code-cursor
      onlyoffice-bin_latest
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
        enableWidevine = true;    # Optional
      })
    ];
  };

  # Set the default editor to helix
  environment.variables.EDITOR = "hx";

  fonts.packages = with pkgs; [
    helvetica-neue-lt-std
    fragment-mono #Helvetica Monospace Coding Font
    aileron #Helvetica font in nine weights

  ];
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
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
    (python312.withPackages (ps:
      with ps; [
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
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

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

  # Optimising the NixOS store with automatic options. This will optimise the
  # store on every build which may slow down builds. The alternativ is to set
  # them on specific dates like this:
  # nix.optimise.automatic = true;
  # nix.optimise.dates = [ "03:45" ]; # Optional; allows customizing schedule
  nix.settings.auto-optimise-store = true;

}

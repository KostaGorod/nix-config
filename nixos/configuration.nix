# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ inputs, config, lib, pkgs, options, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  #nix.channel.enable = true; # not sure if needed at all
  nix = {
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

  };
  nixpkgs.config.allowUnfree = lib.mkForce true; # force allow unfree (if unfree is false by default)

  # Bootloader.
  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "rocinante"; # hostname.
  
  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.
  # Unlock Integrated Modem
  networking.networkmanager.fccUnlockScripts = [ {id = "1eac:1001"; path = "${pkgs.modemmanager}/share/ModemManager/fcc-unlock.available.d/1eac:1001";} ];
  networking.timeServers = [ "timeserver.iix.net.il" ]; # Items in list seperated by space e.g.: [ "time.cloudflare.com" "time.example.com" ];
  services.dnsmasq.enable = true;
  
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
  virtualisation.docker.package = pkgs.docker_26;
  
    
  # fwupdmgr for firmwares updates
  services.fwupd.enable = true;
  
  # bluetooth 
  hardware.bluetooth.enable = true;

  # Logitech unify & solaar (logitech control interface)
  hardware.logitech.wireless.enable = true;
  hardware.logitech.wireless.enableGraphical = true;

  # Locale
  time.timeZone = "Asia/Jerusalem";
  i18n.defaultLocale = "en_US.UTF-8";

  # S3 sleep is great enough
  systemd.targets.hibernate.enable = false;

  #copy current config into etc, this way I can restore config if current evaluation is broken, BEWARE it can contain secrets and such...
  # or just use git
  environment.etc.current-nixos-config.source = ./.; #https://logs.nix.samueldr.com/nixos/2018-06-25#1529934995-1529935276;
  
  
  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  # Using wayland with xwayland instead.
  # Enable the X11 windowing system.
  # services.xserver.enable = true;


  # Enable the GNOME Desktop Environment.
  # services.xserver.displayManager.gdm.enable = true;
  # services.xserver.desktopManager.gnome.enable = true;
  
  # Enable the KDE Plasma6 Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.desktopManager.plasma6.enableQt5Integration = true; # disable for qt6 full version;

  # Fonts
  
 
  # Configure keymap in X11
  # services.xserver.xkb.layout = "us";
  # services.xserver.xkb.options = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  services.printing.enable = true;
  services.printing.drivers = [ pkgs.hplip ];
  services.avahi = { # Printers AutoDiscovery
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

  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;

services.locate = {
enable = true;
localuser = null; # use root, idk why its called null here.
package = pkgs.plocate; # default is locate.
interval = "hourly"; # possible with plocate because it's fast (because incremental)
};

# Power Management
services.power-profiles-daemon.enable = false; # doesn't work with TLP.
# fixing tlp 1.7.0, https://github.com/NixOS/nixpkgs/issues/349759
# probably will be deleted once flake is updated
nixpkgs = {
  overlays =  [
    (final: prev:{
      tlp = prev.tlp.overrideAttrs (old: {
        makeFlags = (old.makeFlags or [ ]) ++ [
          "TLP_ULIB=/lib/udev"
          "TLP_NMDSP=/lib/NetworkManager/dispatcher.d"
          "TLP_SYSD=/lib/systemd/system"
          "TLP_SDSL=/lib/systemd/system-sleep"
          "TLP_ELOD=/lib/elogind/system-sleep"
          "TLP_CONFDPR=/share/tlp/deprecated.conf"
          "TLP_FISHCPL=/share/fish/vendor_completions.d"
          "TLP_ZSHCPL=/share/zsh/site-functions"
        ];
      });
    })
  ];
};
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

  # set user's default shell system-wide
  # users.defaultUserShell = pkgs.nushell;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.kosta = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" ]; # Enable ‘sudo’ for the user. # Enable manage access to NetworkManager
    shell = pkgs.nushell;
    packages = with pkgs; [
      _1password-gui
      firefox
      kdePackages.kdeconnect-kde
      kdePackages.plasma-browser-integration
      pciutils
      remmina #rdp client
      code-cursor
      onlyoffice-bin_latest
      # modified Vivaldi package for native wayland support
      ((vivaldi.overrideAttrs (oldAttrs: {
        # buildInputs = (old.buildInputs or [ ]) ++ [
        #   libsForQt5.qtwayland
        #   libsForQt5.qtx11extras
        #   kdePackages.plasma-integration.qt5
        #   kdePackages.kio-extras-kf5
        #   kdePackages.breeze.qt5c
        # ];
        buildPhase = builtins.replaceStrings
          ["for f in libGLESv2.so libqt5_shim.so ; do"]
          ["for f in libGLESv2.so libqt6_shim.so ; do"]
          oldAttrs.buildPhase;
      })).override {
        qt5 = pkgs.qt6;
        commandLineArgs = [ "--ozone-platform=wayland" ];
        proprietaryCodecs = true; # Optional preference
        enableWidevine = true;    # Optional preference
      })
    ];
  };
  
  # Set the default editor to helix
  environment.variables.EDITOR = "hx";
  
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    helix
    coreutils
    # GUI
    numix-cursor-theme
    # Virtual Keyboard
    maliit-keyboard
    maliit-framework

    # devops ttols
    # docker_26
    kind
    #
    openssl
    gettext
    wget
    jqp
    jp
    httpie
    tailscale
    borgbackup
    easyeffects
    (zed-editor.fhsWithPackages (pkgs: [ pkgs.zlib ])) # zed missing zlib to work is expected https://github.com/xhyrom/zed-discord-presence/issues/12
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
  ];
  services.tailscale.enable = true;
  
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

  # List services that you want to enable:

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
      intel-media-driver
      (if lib.versionOlder (lib.versions.majorMinor lib.version) "23.11" 
       then vaapiIntel 
       else vaapiVdpau)
      libvdpau-va-gl
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


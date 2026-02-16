# System services module
# Printing, audio, power management, firmware updates
{ pkgs, lib, ... }:
{
  # Firmware updates
  services.fwupd.enable = true;

  # Printing (workstation defaults - hosts add drivers and can override)
  services.printing = {
    enable = true;
    listenAddresses = lib.mkDefault [ "*:631" ];
    allowFrom = lib.mkDefault [ "all" ];
    browsing = lib.mkDefault true;
    defaultShared = lib.mkDefault true;
  };

  # Printer discovery (mDNS) - defaults, hosts can override
  services.avahi = {
    enable = lib.mkDefault true;
    nssmdns4 = lib.mkDefault true;
    openFirewall = lib.mkDefault true;
    publish = {
      enable = lib.mkDefault false;
      userServices = lib.mkDefault false;
      addresses = lib.mkDefault false;
      hinfo = lib.mkDefault false;
      workstation = lib.mkDefault false;
    };
    reflector = lib.mkDefault false;
  };

  # Audio (PipeWire)
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa = {
      enable = true;
      support32Bit = true;
    };
  };

  # File indexing
  services.locate = {
    enable = true;
    package = pkgs.plocate;
    interval = "hourly";
  };

  # Power management
  services.power-profiles-daemon.enable = lib.mkDefault false;

  # System76 Scheduler - prioritizes foreground apps, improves responsiveness
  services.system76-scheduler = {
    enable = true;
    useStockConfig = true;
  };

  # TLP defaults live here; hosts opt-in with `services.tlp.enable = true`.
  # Keep this module non-opinionated about enabling power management.
  services.tlp.enable = lib.mkDefault false;

  services.tlp.settings = {
    CPU_SCALING_GOVERNOR_ON_AC = lib.mkDefault "performance";
    CPU_SCALING_GOVERNOR_ON_BAT = lib.mkDefault "powersave";
    CPU_ENERGY_PERF_POLICY_ON_BAT = lib.mkDefault "power";
    CPU_ENERGY_PERF_POLICY_ON_AC = lib.mkDefault "performance";
    PLATFORM_PROFILE_ON_AC = lib.mkDefault "performance";
    PLATFORM_PROFILE_ON_BAT = lib.mkDefault "low-power";
    CPU_MIN_PERF_ON_AC = lib.mkDefault 0;
    CPU_MAX_PERF_ON_AC = lib.mkDefault 100;
    CPU_MIN_PERF_ON_BAT = lib.mkDefault 0;
    CPU_MAX_PERF_ON_BAT = lib.mkDefault 20;
    START_CHARGE_THRESH_BAT0 = lib.mkDefault 40;
    STOP_CHARGE_THRESH_BAT0 = lib.mkDefault 80;
    RUNTIME_PM_ON_AC = lib.mkDefault "on";
    RUNTIME_PM_ON_BAT = lib.mkDefault "auto";
    USB_DENYLIST = lib.mkDefault "0bda:8153";
    MEM_SLEEP_ON_AC = lib.mkDefault "deep";
    MEM_SLEEP_ON_BAT = lib.mkDefault "deep";
    RUNTIME_PM_DRIVER_DENYLIST = lib.mkDefault "mei_me nouveau xhci_hcd";
  };

  # TLP-to-PowerProfiles bridge - hosts enable if they want COSMIC power UI integration.
  services.tlp-power-profiles-bridge.enable = lib.mkDefault false;

  # TeamViewer
  services.teamviewer.enable = true;
}

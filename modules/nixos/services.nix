# System services module
# Printing, audio, power management, firmware updates
{ pkgs, ... }:
{
  # Firmware updates
  services.fwupd.enable = true;

  # Printing
  services.printing = {
    enable = true;
    drivers = [
      pkgs.hplip
      pkgs.pantum-driver
    ];
    listenAddresses = [ "*:631" ];
    allowFrom = [ "all" ];
    browsing = true;
    defaultShared = true;
  };

  # Printer discovery (mDNS)
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    publish = {
      enable = false;
      userServices = false;
      addresses = false;
      hinfo = false;
      workstation = false;
    };
    reflector = false;
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
  services.power-profiles-daemon.enable = false;
  
  # System76 Scheduler - prioritizes foreground apps, improves responsiveness
  services.system76-scheduler = {
    enable = true;
    useStockConfig = true;
  };

  # TLP-to-PowerProfiles bridge - provides D-Bus API for COSMIC power UI
  services.tlp-power-profiles-bridge.enable = true;

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
      START_CHARGE_THRESH_BAT0 = 40;
      STOP_CHARGE_THRESH_BAT0 = 80;
      RUNTIME_PM_ON_AC = "on";
      RUNTIME_PM_ON_BAT = "auto";
      USB_DENYLIST = "0bda:8153";
      MEM_SLEEP_ON_AC = "deep";
      MEM_SLEEP_ON_BAT = "deep";
      RUNTIME_PM_DRIVER_DENYLIST = "mei_me nouveau xhci_hcd";
    };
  };

  # TeamViewer
  services.teamviewer.enable = true;
}

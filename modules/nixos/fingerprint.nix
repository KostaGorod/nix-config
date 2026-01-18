# Fingerprint authentication module for ThinkPad X1 Carbon Gen 9
# Synaptics Prometheus reader (06cb:00fc)
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.fingerprint;
in
{
  options.hardware.fingerprint = {
    enable = lib.mkEnableOption "fingerprint reader support";

    # Enable for specific PAM services
    sudo = lib.mkEnableOption "fingerprint auth for sudo" // { default = true; };
    polkit = lib.mkEnableOption "fingerprint auth for polkit (GUI privilege escalation)" // { default = true; };
    login = lib.mkEnableOption "fingerprint auth for greeter login" // { default = true; };
    screenLock = lib.mkEnableOption "fingerprint auth for screen lock" // { default = true; };
  };

  config = lib.mkIf cfg.enable {
    # Enable fprintd service
    services.fprintd.enable = true;

    # Configure PAM services for fingerprint authentication
    security.pam.services = {
      # sudo - authenticate with fingerprint
      sudo.fprintAuth = cfg.sudo;

      # su - authenticate with fingerprint  
      su.fprintAuth = cfg.sudo;

      # polkit - GUI privilege escalation
      polkit-1.fprintAuth = cfg.polkit;

      # greetd - used by cosmic-greeter and other greetd-based greeters
      greetd.fprintAuth = cfg.login;

      # login - general login PAM service
      login.fprintAuth = cfg.login;

      # COSMIC screen locker (cosmic-greeter uses greetd)
      # Screen lock in COSMIC desktop
    };

    # fprintd CLI tools for enrollment
    environment.systemPackages = with pkgs; [
      fprintd
    ];

    # Ensure PolicyKit is enabled for GUI authentication
    security.polkit.enable = true;
  };
}

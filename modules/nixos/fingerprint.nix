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

  # Script to show fingerprint notification popup
  fingerprint-popup = pkgs.writeShellScriptBin "fingerprint-popup" ''
    # Get the user's display
    export DISPLAY=:0
    export WAYLAND_DISPLAY=''${WAYLAND_DISPLAY:-wayland-1}
    
    # Find user's runtime dir for dbus
    for user_run in /run/user/*; do
      if [ -S "$user_run/bus" ]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=$user_run/bus"
        break
      fi
    done

    # Show notification
    ${pkgs.libnotify}/bin/notify-send \
      --urgency=critical \
      --icon=fingerprint-gui \
      --app-name="Authentication" \
      --expire-time=10000 \
      "🔐 Fingerprint Required" \
      "Place your finger on the sensor" 2>/dev/null || true
  '';

  # Wrapper for fprintd-verify that shows notification
  fprintd-verify-notify = pkgs.writeShellScriptBin "fprintd-verify-notify" ''
    ${fingerprint-popup}/bin/fingerprint-popup &
    exec ${pkgs.fprintd}/bin/fprintd-verify "$@"
  '';
in
{
  options.hardware.fingerprint = {
    enable = lib.mkEnableOption "fingerprint reader support";

    # Enable for specific PAM services
    sudo = lib.mkEnableOption "fingerprint auth for sudo" // { default = true; };
    polkit = lib.mkEnableOption "fingerprint auth for polkit (GUI privilege escalation)" // { default = true; };
    login = lib.mkEnableOption "fingerprint auth for greeter login" // { default = false; };
    screenLock = lib.mkEnableOption "fingerprint auth for screen lock" // { default = true; };
  };

  config = lib.mkIf cfg.enable {
    # Enable fprintd service
    services.fprintd.enable = true;

    # Configure PAM services for fingerprint authentication
    security.pam.services = {
      # sudo/su: fingerprint with password fallback
      sudo.fprintAuth = cfg.sudo;
      su.fprintAuth = cfg.sudo;
      
      # polkit: fingerprint for GUI privilege escalation
      polkit-1.fprintAuth = cfg.polkit;
      
      # Login: password only (to unlock keyring)
      greetd.fprintAuth = cfg.login;
      cosmic-greeter.fprintAuth = cfg.login;
      login.fprintAuth = cfg.login;
      
      # Screen lock: fingerprint for quick unlock
      swaylock.fprintAuth = cfg.screenLock;
      hyprlock.fprintAuth = cfg.screenLock;
    };

    # fprintd CLI tools for enrollment + notification helper
    environment.systemPackages = with pkgs; [
      fprintd
      libnotify
      fingerprint-popup
      fprintd-verify-notify
    ];

    # Ensure PolicyKit is enabled for GUI authentication
    security.polkit.enable = true;
  };
}

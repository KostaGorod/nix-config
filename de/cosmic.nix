{
  config,
  lib,
  pkgs,
  ...
}:

{
  services = {
    # Use COSMIC's greeter (greetd + cosmic-greeter)
    displayManager.cosmic-greeter.enable = true;

    # Enable COSMIC desktop environment
    desktopManager.cosmic.enable = true;

    # Workaround: cosmic-greeter expects a session bus.
    # greetd does not reliably export DBUS_SESSION_BUS_ADDRESS, which can leave
    # the greeter stuck showing only background + cursor.
    greetd.settings.default_session.command = lib.mkForce ''${lib.getExe' pkgs.dbus "dbus-run-session"} -- ${lib.getExe' pkgs.coreutils "env"} XCURSOR_THEME="''${XCURSOR_THEME:-Pop}" ${lib.getExe' config.services.displayManager.cosmic-greeter.package "cosmic-greeter-start"}'';
  };

  # Performance optimizations for COSMIC
  services.system76-scheduler.enable = true;

  # Enable clipboard manager (bypasses Wayland security)
  environment.sessionVariables.COSMIC_DATA_CONTROL_ENABLED = "1";

  # Optional: Exclude specific COSMIC packages if needed
  # environment.cosmic.excludePackages = with pkgs; [
  #   cosmic-edit
  # ];
}

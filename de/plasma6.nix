_:

{
  services = {
    displayManager.sddm.enable = false;
    displayManager.sddm.wayland.enable = false;

    desktopManager.plasma6.enable = true;
    desktopManager.plasma6.enableQt5Integration = true; # disable for qt6 full version;
  };

  # programs.dconf.enable = true; # for GNOME, currently using KDE
}

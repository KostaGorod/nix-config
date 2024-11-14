{ config, pkgs, ... }:
 
{
  services = {
    displayManager.sddm.enable = true;
    displayManager.sddm.wayland.enable = true;
    
    desktopManager.plasma6.enable = true;
    desktopManager.plasma6.enableQt5Integration = true; # disable for qt6 full version;
    };

  # programs.dconf.enable = true; # for GNOME, currently using KDE
}

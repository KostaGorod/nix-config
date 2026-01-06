{ config, pkgs, ... }:

{
  services = {
    desktopManager.cosmic.enable = true;
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
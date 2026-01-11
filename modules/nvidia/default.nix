{ config, lib, pkgs, ... }:

{
  # =============================================================================
  # NVIDIA DRIVER CONFIGURATION
  # =============================================================================
  
  # Enable OpenGL/Vulkan
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # Load NVIDIA driver for Xorg and Wayland
  services.xserver.videoDrivers = ["nvidia"];

  hardware.nvidia = {
    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    # Enable this if you have graphical corruption issues or application crashes after waking
    # up from sleep. This fixes it by saving the entire VRAM memory to /tmp/
    powerManagement.enable = false;

    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = false;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" driver).
    # Support is limited to the Turing and later architectures. Full support of
    # GeForce and Workstation GPUs.
    open = false;  # Use proprietary for better CUDA compatibility usually

    # Enable the Nvidia settings menu,
    # accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Package choice: Stable or Beta or Production
    package = config.boot.kernelPackages.nvidiaPackages.production;
  };

  # Persistence mode should be OFF by default to allow unbinding
  systemd.services.nvidia-persistenced = {
    enable = false;
  };
  
  # Ensure CUDA is available
  environment.systemPackages = with pkgs; [
    cudaPackages.cudatoolkit
    linuxPackages.nvidia_x11
  ];
}

{ config, lib, pkgs, ... }:

{
  # =============================================================================
  # NVIDIA DRIVER CONFIGURATION
  # For GPU compute (K3s AI workloads) with support for dynamic VFIO switching
  # =============================================================================
  
  # Enable OpenGL/Vulkan
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # NOTE: X11/Wayland desktop drivers are disabled on this host because
  # hardware.nvidia.datacenter.enable = true below uses the data-center
  # kernel driver, which conflicts with X11. If you ever need a GUI on
  # this machine, disable datacenter mode and re-enable videoDrivers.

  hardware.nvidia = {
    # Modesetting is required
    modesetting.enable = true;

    # Power management OFF - we want predictable behavior for switching
    powerManagement.enable = false;
    powerManagement.finegrained = false;

    # Use proprietary driver for best CUDA/compute compatibility
    open = false;

    # No GUI settings menu needed on a server/compute node
    nvidiaSettings = false;

    # Production driver for stability
    package = config.boot.kernelPackages.nvidiaPackages.production;
  };

  # =============================================================================
  # NIXPKGS NVIDIA SETTINGS
  # =============================================================================
  nixpkgs.config.nvidia.acceptLicense = true;
  hardware.nvidia.datacenter.enable = true;

  # =============================================================================
  # NVIDIA CONTAINER TOOLKIT (for K3s GPU workloads)
  # =============================================================================
  hardware.nvidia-container-toolkit = {
    enable = true;
    # Mount nvidia devices into containers
    mount-nvidia-executables = true;
  };

  # =============================================================================
  # PERSISTENCE MODE
  # OFF by default to allow driver unbinding for VFIO switching
  # When GPU is in "AI mode", we can optionally enable it for performance
  # =============================================================================
  systemd.services.nvidia-persistenced.enable = false;
  
  # =============================================================================
  # PACKAGES
  # =============================================================================
  environment.systemPackages = with pkgs; [
    cudaPackages.cudatoolkit
    nvtopPackages.full
  ];
}

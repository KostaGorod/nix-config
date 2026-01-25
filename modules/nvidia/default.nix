{ config, pkgs, ... }:

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

  # NOTE: services.xserver.videoDrivers is set to load the nvidia kernel module.
  # This does NOT require X11/Wayland - it just ensures the nvidia driver loads
  # for compute/container workloads. Works headless.

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

  # Load nvidia kernel driver (required for container-toolkit and K3s GPU access)
  # NOTE: datacenter.enable is NOT needed for consumer GPUs (RTX 2070, 3080, 4090, etc.)
  # Datacenter mode is only for Tesla, A100, H100 with NVLink/NVSwitch topologies
  services.xserver.videoDrivers = [ "nvidia" ];

  # =============================================================================
  # NVIDIA CONTAINER TOOLKIT (for K3s GPU workloads)
  # =============================================================================
  hardware.nvidia-container-toolkit = {
    enable = true;
    # Mount nvidia devices into containers
    mount-nvidia-executables = true;
  };

  # The NixOS nvidia-container-toolkit module provides nvidia-container-toolkit-cdi-generator.service
  # which generates /var/run/cdi/nvidia.yaml. However it may run before nvidia driver is loaded.
  # Add retry logic since the driver might not be fully ready immediately after boot.
  systemd.services.nvidia-container-toolkit-cdi-generator = {
    after = [ "systemd-modules-load.service" ];
    # Add retry - the driver might not be fully ready immediately
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "5s";
    };
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

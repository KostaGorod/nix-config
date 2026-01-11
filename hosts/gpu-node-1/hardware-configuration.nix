# Hardware configuration for GPU Node 1
# AMD Ryzen 5 3400G + 2x NVIDIA RTX 3080
#
# NOTE: This is a template. Run `nixos-generate-config` on the actual
# hardware to get accurate values for filesystems and kernel modules.

{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # =============================================================================
  # BOOT
  # =============================================================================
  boot.initrd.availableKernelModules = [ 
    "nvme" 
    "xhci_pci" 
    "ahci" 
    "usbhid" 
    "sd_mod" 
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  # =============================================================================
  # FILESYSTEMS
  # =============================================================================
  # TODO: Update these after running nixos-generate-config on actual hardware
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
  };

  swapDevices = [
    { device = "/dev/disk/by-label/swap"; }
  ];

  # =============================================================================
  # HARDWARE
  # =============================================================================
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  
  # Enable all firmware
  hardware.enableRedistributableFirmware = true;
  hardware.enableAllFirmware = true;

  # GPU - handled by nvidia module
  # 2x RTX 3080 should be detected automatically

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}

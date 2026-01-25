# Hardware configuration for GPU Node 1
# AMD Ryzen 5 3400G + 2x NVIDIA RTX 3080
#
# Minimal config - nixos-anywhere will generate accurate values
# after first boot with `nixos-generate-config`

{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # =============================================================================
  # BOOT
  # =============================================================================
  boot.initrd.availableKernelModules = [ 
    "ahci" 
    "xhci_pci" 
    "virtio_pci" 
    "virtio_scsi"
    "sd_mod" 
    "sr_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  # Filesystems are managed by disko - no need to declare here

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

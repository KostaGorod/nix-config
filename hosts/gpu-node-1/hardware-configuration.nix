# Hardware configuration for GPU Node 1
# Proxmox VM with Intel vCPU + 1x NVIDIA RTX 2070 Super (passthrough)
#
# VM ID: 102 on Proxmox
# Machine type: q35 with OVMF UEFI

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
    # VFIO modules for nested GPU passthrough
    "vfio_pci"
    "vfio"
    "vfio_iommu_type1"
  ];
  boot.initrd.kernelModules = [ ];
  # Intel KVM for nested virtualization (Proxmox exposes Intel vCPU)
  boot.kernelModules = [ "kvm-intel" "vfio_pci" "vfio" "vfio_iommu_type1" ];
  boot.extraModulePackages = [ ];

  # VFIO options for GPU passthrough
  boot.extraModprobeConfig = ''
    # Allow VFIO to work without VGA arbitration issues
    options vfio-pci disable_vga=1
    # Ensure VFIO loads before NVIDIA so we can choose which driver binds
    softdep nvidia pre: vfio-pci
  '';

  # Filesystems are managed by disko - no need to declare here

  # =============================================================================
  # HARDWARE
  # =============================================================================
  # Intel microcode for Proxmox's Intel vCPU
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  
  # Enable all firmware
  hardware.enableRedistributableFirmware = true;
  hardware.enableAllFirmware = true;

  # GPU - RTX 2070 Super passed through from Proxmox
  # Handled by nvidia module when in AI mode
  # Handled by vfio-pci when in gaming mode (Windows VM)

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}

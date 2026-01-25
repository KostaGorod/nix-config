# VFIO module for GPU passthrough to nested VMs
# Enables driver switching between nvidia and vfio-pci
{ pkgs, ... }:

{
  # Note: Kernel modules are loaded in hardware-configuration.nix (boot.initrd + boot.kernelModules)
  # This module provides utilities and ensures runtime VFIO support

  # Utility to check IOMMU groups (essential for debugging passthrough)
  environment.systemPackages = with pkgs; [
    (writeShellScriptBin "iommu-groups" ''
      #!/usr/bin/env bash
      # List all IOMMU groups and their devices
      if [[ ! -d /sys/kernel/iommu_groups ]]; then
        echo "ERROR: No IOMMU groups found. Is vIOMMU enabled in Proxmox?"
        echo "Add to VM: -args '-device intel-iommu,intremap=on,caching-mode=on'"
        exit 1
      fi

      for d in /sys/kernel/iommu_groups/*/devices/*; do
        n=$(basename $(dirname $(dirname $d)))
        echo "IOMMU Group $n: $(${pkgs.pciutils}/bin/lspci -nns "''${d##*/}")"
      done | sort -V
    '')

    (writeShellScriptBin "gpu-driver-status" ''
      #!/usr/bin/env bash
      # Show current GPU driver bindings
      echo "=== GPU Driver Status ==="
      for dev in /sys/bus/pci/devices/*; do
        if [[ -f "$dev/class" ]] && grep -q "^0x03" "$dev/class" 2>/dev/null; then
          pci=$(basename "$dev")
          driver="none"
          if [[ -L "$dev/driver" ]]; then
            driver=$(basename $(readlink "$dev/driver"))
          fi
          echo "$pci: $driver ($(${pkgs.pciutils}/bin/lspci -s "$pci" -nn | cut -d: -f3-))"
        fi
      done
    '')
  ];
}

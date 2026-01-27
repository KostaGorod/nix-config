# Libvirt/QEMU configuration for hosting Windows gaming VM
# Configured for nested virtualization with GPU passthrough
{ pkgs, ... }:

{
  virtualisation.libvirtd = {
    enable = true;

    qemu = {
      package = pkgs.qemu_kvm;

      # OVMF (UEFI) is now included by default in NixOS 25.11+
      # No need to explicitly enable it

      # TPM emulation (required for Windows 11)
      swtpm.enable = true;

      # Permissions for VFIO passthrough
      # Running as root is simplest for nested passthrough
      verbatimConfig = ''
        user = "root"
        group = "root"
        cgroup_device_acl = [
          "/dev/null", "/dev/full", "/dev/zero",
          "/dev/random", "/dev/urandom",
          "/dev/ptmx", "/dev/kvm",
          "/dev/vfio/vfio"
        ]
      '';
    };
  };

  # VM management tools
  environment.systemPackages = with pkgs; [
    virt-manager
    virt-viewer
    spice-gtk
    libguestfs # For disk image manipulation
    virtio-win # Windows VirtIO drivers ISO
    looking-glass-client # Low-latency display for GPU passthrough
  ];

  # Ensure libvirtd group exists and kosta is in it
  users.groups.libvirtd = { };
}

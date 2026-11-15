_: {
  nixos.modules.workstation =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.virtualisation.libvirt;
    in
    {
      options.virtualisation.libvirt = {
        enable = lib.mkEnableOption "libvirt with virt-manager, UEFI and virtual TPM support";

        users = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "kosta" ];
          description = "Users granted access to manage system virtual machines.";
        };
      };

      config = lib.mkIf cfg.enable {
        programs.virt-manager.enable = true;
        virtualisation.libvirtd = {
          enable = true;
          qemu = {
            package = pkgs.qemu_kvm;
            swtpm.enable = true;
          };
        };
        # The native libvirtd module provides UEFI/Secure Boot firmware.
        users.users = lib.genAttrs cfg.users (_user: {
          extraGroups = [ "libvirtd" ];
        });
      };
    };
}

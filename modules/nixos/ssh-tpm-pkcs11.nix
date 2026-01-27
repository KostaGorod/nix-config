# SSH with TPM PKCS#11 authentication module
# Enables SSH key storage in TPM for hardware-backed security
# Reference: https://wiki.nixos.org/wiki/TPM
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.security.ssh-tpm;
in
{
  options.security.ssh-tpm = {
    enable = lib.mkEnableOption "SSH with TPM PKCS#11 key storage";

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of users to grant TPM access (added to tss group)";
      example = [ "kosta" ];
    };
  };

  config = lib.mkIf cfg.enable {
    # Enable TPM2 support (per wiki.nixos.org/wiki/TPM)
    security.tpm2 = {
      enable = true;
      pkcs11.enable = true;           # Expose libtpm2_pkcs11.so
      tctiEnvironment.enable = true;  # Set TPM2TOOLS_TCTI and TPM2_PKCS11_TCTI
    };

    # Configure SSH agent to allow TPM PKCS#11 module loading
    programs.ssh = {
      startAgent = true;
      agentPKCS11Whitelist = "${config.security.tpm2.pkcs11.package}/lib/*";
    };

    # Add specified users to tss group for TPM access
    users.users = lib.genAttrs cfg.users (user: {
      extraGroups = [ "tss" ];
    });

    # Only tpm2-pkcs11 needed for tpm2_ptool commands
    environment.systemPackages = [
      pkgs.tpm2-pkcs11
    ];
  };
}

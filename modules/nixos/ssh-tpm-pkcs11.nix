# SSH with TPM PKCS#11 and FIDO2/YubiKey authentication module
# Enables SSH key storage in TPM for hardware-backed security
# Also configures SSH askpass for FIDO2 PIN prompts
# Reference: https://wiki.nixos.org/wiki/TPM
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.security.ssh-tpm;
  askpass = pkgs.lxqt.lxqt-openssh-askpass;
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
      pkcs11.enable = true; # Expose libtpm2_pkcs11.so
      tctiEnvironment.enable = true; # Set TPM2TOOLS_TCTI and TPM2_PKCS11_TCTI
    };

    # Configure SSH agent to allow TPM PKCS#11 module loading
    # askPassword: GUI prompt for FIDO2 PIN (required for verify-required SK keys)
    programs.ssh = {
      startAgent = true;
      agentPKCS11Whitelist = "${config.security.tpm2.pkcs11.package}/lib/*";
      askPassword = "${askpass}/bin/lxqt-openssh-askpass";
    };

    # Disable GNOME Keyring / GCR SSH agent; we want OpenSSH's `ssh-agent`.
    # Otherwise GNOME Keyring exports SSH_AUTH_SOCK=/run/user/$UID/keyring/ssh.
    services.gnome.gnome-keyring.enable = lib.mkForce false;
    services.gnome.gcr-ssh-agent.enable = lib.mkForce false;

    # Set SSH_AUTH_SOCK globally (PAM), so all shells + GUI apps agree.
    environment.sessionVariables = {
      # pam_env requires expandable variables to be wrapped in ${...}
      SSH_AUTH_SOCK = "\${XDG_RUNTIME_DIR}/ssh-agent";
      SSH_ASKPASS_REQUIRE = "prefer";
    };

    # Extra safeguard for POSIX shells.
    # SSH_ASKPASS must be set here because NixOS defaults it to "" in set-environment
    environment.extraInit = ''
      export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent"
      export SSH_ASKPASS="${askpass}/bin/lxqt-openssh-askpass"
      export SSH_ASKPASS_REQUIRE="prefer"
    '';

    # Add specified users to tss group for TPM access
    users.users = lib.genAttrs cfg.users (_user: {
      extraGroups = [ "tss" ];
    });

    # Packages for TPM and FIDO2 SSH
    environment.systemPackages = [
      pkgs.tpm2-pkcs11
      askpass # SSH askpass for FIDO2 PIN prompts
    ];
  };
}

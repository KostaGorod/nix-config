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

    # Keep OpenSSH's `ssh-agent` authoritative.
    # GNOME Keyring is useful for Secret Service (org.freedesktop.secrets), so
    # don't globally disable it here; instead, make sure it doesn't provide an
    # SSH agent socket by default.
    #services.gnome.gnome-keyring.components = lib.mkDefault [
    #  "secrets"
    #  "pkcs11"
    #];
    services.gnome.gcr-ssh-agent.enable = lib.mkForce false;

    # Set SSH_AUTH_SOCK globally (PAM), so all shells + GUI apps agree.
    # pam_env requires `${VAR}` syntax; `$VAR` is treated as a literal string
    # and ends up propagating an unexpanded value into the systemd user env.
    environment.sessionVariables = {
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

    # The upstream ssh-agent user unit (from programs.ssh.startAgent) hardcodes
    # `DISPLAY=fake` and `SSH_ASKPASS=""`, which disables any GUI askpass and
    # breaks FIDO2 PIN entry for `verify-required` sk keys (the agent silently
    # treats the missing PIN as an incorrect one and refuses to sign).
    # Override so the agent uses the real askpass and inherits the display env.
    # Also tie the lifecycle to graphical-session.target: the default unit is
    # pulled in by default.target, which activates before cosmic-session
    # imports DISPLAY/WAYLAND_DISPLAY — so PassEnvironment would otherwise
    # capture nothing at boot.
    systemd.user.services.ssh-agent = {
      wantedBy = lib.mkForce [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        Environment = lib.mkForce [
          "SSH_ASKPASS=${askpass}/bin/lxqt-openssh-askpass"
          "SSH_ASKPASS_REQUIRE=prefer"
        ];
        PassEnvironment = "DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR";
      };
    };

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

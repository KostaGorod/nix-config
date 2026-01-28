# YubiKey and FIDO2 support module
# Provides hardware security key authentication for SSH, PAM, and GPG
#
# Usage:
#   hardware.yubikey.enable = true;           # Enables libfido2 for SSH *-sk keys
#   hardware.yubikey.pcscd = true;            # Smart card daemon (PIV/PGP)
#   hardware.yubikey.u2fAuth.sudo = true;     # U2F for sudo
#   hardware.yubikey.gpgAgent.enable = true;  # GPG agent with SSH support
#
# After enabling, test with:
#   ykman info                    # YubiKey status
#   ssh-keygen -t ed25519-sk      # Create FIDO2 SSH key
#   ssh-keygen -t ecdsa-sk        # Alternative FIDO2 SSH key
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.yubikey;
in
{
  options.hardware.yubikey = {
    enable = lib.mkEnableOption "YubiKey and FIDO2 support (libfido2 for SSH *-sk keys)";

    pcscd = lib.mkEnableOption "PC/SC daemon for smart card access (required for PIV/PGP)" // {
      default = false;
    };

    tools = lib.mkEnableOption "YubiKey management tools (ykman, yubikey-personalization)" // {
      default = false;
    };

    u2fAuth = {
      sudo = lib.mkEnableOption "U2F/FIDO2 authentication for sudo" // {
        default = false;
      };
      login = lib.mkEnableOption "U2F/FIDO2 authentication for login" // {
        default = false;
      };
      polkit = lib.mkEnableOption "U2F/FIDO2 authentication for polkit (GUI privilege escalation)" // {
        default = false;
      };
      screenLock = lib.mkEnableOption "U2F/FIDO2 authentication for screen lock (swaylock/hyprlock)" // {
        default = false;
      };
    };

    gpgAgent = {
      enable = lib.mkEnableOption "GPG agent (for YubiKey PGP operations)" // {
        default = false;
      };
      enableSSHSupport = lib.mkEnableOption "Use GPG agent for SSH authentication" // {
        default = false;
      };
      pinentryPackage = lib.mkOption {
        type = lib.types.package;
        default = pkgs.pinentry-curses;
        description = "Pinentry program for GPG passphrase entry";
        example = lib.literalExpression "pkgs.pinentry-qt";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Core FIDO2 library - required for ssh-keygen -t ed25519-sk / ecdsa-sk
    environment.systemPackages =
      with pkgs;
      [
        libfido2 # FIDO2/WebAuthn library with fido2-token CLI
      ]
      ++ lib.optionals cfg.tools [
        yubikey-manager # ykman CLI for YubiKey configuration
        yubikey-personalization # ykpersonalize for OTP slot programming
        yubico-piv-tool # PIV management
      ]
      ++ lib.optionals cfg.gpgAgent.enable [
        gnupg
        cfg.gpgAgent.pinentryPackage
      ];

    # PC/SC daemon for smart card communication (PIV, PGP on YubiKey)
    services.pcscd.enable = cfg.pcscd;

    # udev rules for YubiKey device access
    services.udev.packages = lib.mkIf cfg.tools [
      pkgs.yubikey-personalization
    ];

    # GPG agent configuration
    programs.gnupg.agent = lib.mkIf cfg.gpgAgent.enable {
      enable = true;
      inherit (cfg.gpgAgent) enableSSHSupport;
      inherit (cfg.gpgAgent) pinentryPackage;
    };

    # PAM U2F authentication
    # Requires: pamu2fcfg > ~/.config/Yubico/u2f_keys
    security.pam.u2f =
      lib.mkIf (cfg.u2fAuth.sudo || cfg.u2fAuth.login || cfg.u2fAuth.polkit || cfg.u2fAuth.screenLock)
        {
          enable = true;
          # cue = true;  # Uncomment to show "Please touch the device" prompt
          # interactive = true;  # Uncomment for interactive prompts
          control = "sufficient"; # U2F success is enough (fallback to password)
          # control = "required";  # Uncomment to require U2F (no fallback)
        };

    security.pam.services =
      lib.mkIf (cfg.u2fAuth.sudo || cfg.u2fAuth.login || cfg.u2fAuth.polkit || cfg.u2fAuth.screenLock)
        {
          # sudo/su: U2F authentication
          sudo.u2fAuth = cfg.u2fAuth.sudo;
          su.u2fAuth = cfg.u2fAuth.sudo;

          # polkit: U2F for GUI privilege escalation
          polkit-1.u2fAuth = cfg.u2fAuth.polkit;

          # Login: U2F authentication
          login.u2fAuth = cfg.u2fAuth.login;
          greetd.u2fAuth = cfg.u2fAuth.login;

          # Screen lock: U2F authentication
          swaylock.u2fAuth = cfg.u2fAuth.screenLock;
          hyprlock.u2fAuth = cfg.u2fAuth.screenLock;
        };
  };
}

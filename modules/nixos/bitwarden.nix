{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.programs.bitwarden;

  pkgs-unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };
in
{
  options.programs.bitwarden = {
    enable = lib.mkEnableOption "Bitwarden desktop password manager";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs-unstable.bitwarden-desktop;
      description = "The Bitwarden desktop package to use";
    };
  };

  config = lib.mkIf cfg.enable {
    # Bitwarden Desktop uses the Freedesktop Secret Service API for secure
    # credential storage. On NixOS this is typically provided by gnome-keyring.
    # Without it you'll see errors like:
    #   org.freedesktop.zbus.Error: The name org.freedesktop.secrets was not provided
    # and Bitwarden will fall back to disk storage (and can sometimes misbehave).
    services.gnome.gnome-keyring = {
      enable = lib.mkDefault true;
      # Avoid clobbering SSH_AUTH_SOCK; we use OpenSSH's ssh-agent.
      #components = lib.mkDefault [
      #  "secrets"
      #  "pkcs11"
      #];
    };

    # COSMIC uses greetd; ensure the keyring is started/unlocked via PAM.
    security.pam.services.greetd.enableGnomeKeyring = lib.mkDefault true;
    security.pam.services.login.enableGnomeKeyring = lib.mkDefault true;

    environment.systemPackages = [
      cfg.package
    ];
  };
}

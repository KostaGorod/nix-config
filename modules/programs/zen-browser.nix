# Zen Browser workstation configuration
# Disables built-in password manager to use Bitwarden instead
_: {
  nixos.modules.workstation =
    { pkgs, ... }:
    let
      userJsContent = ''
        // Managed by NixOS - Disable built-in password manager
        // Use Bitwarden extension instead

        // Disable password saving prompts
        user_pref("signon.rememberSignons", false);

        // Disable autofill of saved passwords
        user_pref("signon.autofillForms", false);

        // Disable password generation
        user_pref("signon.generation.enabled", false);

        // Disable Firefox Relay integration
        user_pref("signon.firefoxRelay.feature", "disabled");

        // Don't show password breach alerts (Bitwarden handles this)
        user_pref("signon.management.page.breach-alerts.enabled", false);

        // Disable "save password" infobar completely
        user_pref("signon.rememberSignons.visibilityToggle", false);
      '';
      userJsFile = pkgs.writeText "zen-user.js" userJsContent;
    in
    {
      systemd.services.zen-browser-config = {
        description = "Zen Browser config for password manager";
        after = [ "local-fs.target" ];
        wantedBy = [ "multi-user.target" ];
        restartIfChanged = true;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "kosta";
          Group = "users";
          ExecStart = "${pkgs.writeShellScriptBin "zen-browser-config" ''
            target="/home/kosta/.zen/qodg0ptz.Default Profile/user.js"
            ${pkgs.coreutils}/bin/mkdir -p "/home/kosta/.zen/qodg0ptz.Default Profile"
            if [ -L "$target" ]; then
              echo "refusing to replace symlink: $target" >&2
              exit 1
            fi
            ${pkgs.coreutils}/bin/install -m 0644 "${userJsFile}" "$target"
          ''}/bin/zen-browser-config";
        };
      };
    };
}

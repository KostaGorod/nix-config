# Zen Browser configuration
# Disables built-in password manager to use Bitwarden instead
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
in
{
  systemd.user.services.zen-browser-config = {
    description = "Zen Browser config for password manager";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.writeShellScriptBin "zen-browser-config" ''
                mkdir -p ~/.zen/qodg0ptz.Default\ Profile
                cat > ~/.zen/qodg0ptz.Default\ Profile/user.js << 'EOF'
        ${userJsContent}
        EOF
      ''}/bin/zen-browser-config";
    };
    wantedBy = [ "default.target" ];
  };
}

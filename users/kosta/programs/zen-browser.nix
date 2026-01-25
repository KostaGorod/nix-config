# Zen Browser configuration
# Disables built-in password manager to use Bitwarden instead
_:
let
  # Zen Browser stores profiles in ~/.zen/ (Firefox-like structure)
  # Profile name is dynamic but can be found via profiles.ini
  zenProfileDir = ".zen/qodg0ptz.Default Profile";
in
{
  # Create user.js with password manager settings disabled
  # user.js is read on browser startup and overrides prefs
  home.file."${zenProfileDir}/user.js".text = ''
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
}

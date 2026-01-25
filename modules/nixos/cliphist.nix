# Cliphist - Wayland clipboard history with password manager support
# Uses wl-clipboard-sensitive (git version) that respects x-kde-passwordManagerHint
# Bitwarden, KeePassXC, 1Password will NOT have passwords stored in history
{ pkgs, ... }:

let
  # Apply the overlay to get wl-clipboard with sensitive support
  wl-clipboard-sensitive = pkgs.wl-clipboard.overrideAttrs (old: {
    version = "2.2.1-unstable-2025-11-24";

    src = pkgs.fetchFromGitHub {
      owner = "bugaevc";
      repo = "wl-clipboard";
      rev = "e8082035dafe0241739d7f7d16f7ecfd2ce06172";
      hash = "sha256-sR/P+urw3LwAxwjckJP3tFeUfg5Axni+Z+F3mcEqznw=";
    };

    buildInputs = old.buildInputs ++ [ pkgs.wayland-protocols ];
  });

  cliphist-secure-store = pkgs.writeShellScriptBin "cliphist-secure-store" ''
    ${pkgs.cliphist}/bin/cliphist store
    chmod 600 "$HOME/.cache/cliphist/db" 2>/dev/null || true
  '';

  clipboard-picker = pkgs.callPackage ../../packages/clipboard-picker {
    wl-clipboard = wl-clipboard-sensitive;
  };
in
{
  # Install the packages system-wide
  environment.systemPackages = [
    wl-clipboard-sensitive
    pkgs.cliphist
    pkgs.rofi
    pkgs.zenity
    clipboard-picker
  ];

  # Create a systemd user service to run the clipboard watcher
  systemd.user.services.cliphist = {
    description = "Clipboard history service for Wayland";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];

    serviceConfig = {
      Type = "simple";
      # Use secure wrapper that sets chmod 600 after each store
      ExecStart = "${wl-clipboard-sensitive}/bin/wl-paste --watch ${cliphist-secure-store}/bin/cliphist-secure-store";
      Restart = "on-failure";
      RestartSec = 1;
    };

  };

  # Also watch primary selection (middle-click paste)
  systemd.user.services.cliphist-primary = {
    description = "Primary selection history service for Wayland";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];

    serviceConfig = {
      Type = "simple";
      # Use secure wrapper that sets chmod 600 after each store
      ExecStart = "${wl-clipboard-sensitive}/bin/wl-paste --primary --watch ${cliphist-secure-store}/bin/cliphist-secure-store";
      Restart = "on-failure";
      RestartSec = 1;
    };
  };

  # Ensure secure permissions on first boot / if db exists
  system.activationScripts.cliphist-secure = ''
    for user_home in /home/*; do
      db_file="$user_home/.cache/cliphist/db"
      if [ -f "$db_file" ]; then
        chmod 600 "$db_file"
      fi
    done
  '';
}

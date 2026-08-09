# Encrypted text-only clipboard history for Wayland
# Password-manager entries are rejected through CLIPBOARD_STATE=sensitive.
_: {
  nixos.modules.workstation =
    { lib, pkgs, ... }:

    let
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

      cliphist-secure = pkgs.callPackage ../../packages/cliphist-secure { };
      clipboard-picker = pkgs.callPackage ../../packages/clipboard-picker {
        cliphist = cliphist-secure;
        wl-clipboard = wl-clipboard-sensitive;
      };

      cliphistCommand = "${cliphist-secure}/bin/cliphist";

      watcherHardening = {
        UMask = "0077";
        LimitCORE = 0;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectHome = "read-only";
        ProtectSystem = "strict";
        ReadWritePaths = [
          "%h/.local/state/cliphist-vault"
          "%t/cliphist-vault"
        ];
        RestrictAddressFamilies = [ "AF_UNIX" ];
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictSUIDSGID = true;
      };
    in
    {
      # The vault key is stored in Secret Service. Keep this independent from
      # Bitwarden's module so clipboard encryption cannot silently lose its backend.
      services.gnome.gnome-keyring.enable = lib.mkDefault true;
      security.pam.services.greetd.enableGnomeKeyring = lib.mkDefault true;
      security.pam.services.login.enableGnomeKeyring = lib.mkDefault true;

      environment.systemPackages = [
        wl-clipboard-sensitive
        cliphist-secure
        pkgs.rofi
        pkgs.zenity
        clipboard-picker
      ];

      # Initialize and validate the persistent SQLCipher database before the
      # clipboard watchers start. No plaintext mount or privileged helper is used.
      systemd.user.services.cliphist-vault = {
        description = "Encrypted clipboard history database";
        wantedBy = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];

        serviceConfig = watcherHardening // {
          Type = "oneshot";
          ExecStart = "${cliphistCommand} init";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = 2;
          TimeoutStartSec = 20;

          StateDirectory = "cliphist-vault";
          StateDirectoryMode = "0700";
          RuntimeDirectory = "cliphist-vault";
          RuntimeDirectoryMode = "0700";
        };
      };

      systemd.user.services.cliphist = {
        description = "Encrypted clipboard history watcher";
        wantedBy = [ "graphical-session.target" ];
        requires = [ "cliphist-vault.service" ];
        partOf = [
          "graphical-session.target"
          "cliphist-vault.service"
        ];
        after = [
          "graphical-session.target"
          "cliphist-vault.service"
        ];

        serviceConfig = watcherHardening // {
          Type = "simple";
          # --type must precede --watch so non-text offers never reach cliphist.
          ExecStart = "${wl-clipboard-sensitive}/bin/wl-paste --type text --watch ${cliphistCommand} store";
          Restart = "on-failure";
          RestartSec = 1;
        };
      };

      systemd.user.services.cliphist-primary = {
        description = "Encrypted primary-selection history watcher";
        wantedBy = [ "graphical-session.target" ];
        requires = [ "cliphist-vault.service" ];
        partOf = [
          "graphical-session.target"
          "cliphist-vault.service"
        ];
        after = [
          "graphical-session.target"
          "cliphist-vault.service"
        ];

        serviceConfig = watcherHardening // {
          Type = "simple";
          ExecStart = "${wl-clipboard-sensitive}/bin/wl-paste --primary --type text --watch ${cliphistCommand} store";
          Restart = "on-failure";
          RestartSec = 1;
        };
      };
    };
}

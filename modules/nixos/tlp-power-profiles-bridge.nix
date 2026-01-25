{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.tlp-power-profiles-bridge;
  
  bridgePackage = pkgs.callPackage ../../packages/tlp-power-profiles-bridge { };
in
{
  options.services.tlp-power-profiles-bridge = {
    enable = lib.mkEnableOption "TLP to power-profiles-daemon D-Bus bridge for COSMIC";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.tlp.enable;
        message = "tlp-power-profiles-bridge requires TLP to be enabled";
      }
      {
        assertion = !config.services.power-profiles-daemon.enable;
        message = "tlp-power-profiles-bridge conflicts with power-profiles-daemon";
      }
    ];

    environment.systemPackages = [ bridgePackage ];

    services.dbus.packages = [ bridgePackage ];

    systemd.services.tlp-power-profiles-bridge = {
      description = "TLP to power-profiles-daemon D-Bus Bridge";
      wantedBy = [ "multi-user.target" ];
      after = [ "dbus.service" "tlp.service" ];
      requires = [ "dbus.service" ];

      environment = {
        TLP_PATH = "${pkgs.tlp}/bin/tlp";
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${bridgePackage}/bin/tlp-power-profiles-bridge";
        Restart = "on-failure";
        RestartSec = 5;

        User = "root";

        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = false;
        ReadOnlyPaths = [ "/" ];
        ReadWritePaths = [ "/sys" ];
      };
    };
  };
}

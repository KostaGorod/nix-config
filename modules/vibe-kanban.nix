{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.services.vibe-kanban;
  vibe-kanban-flake = inputs.vibe-kanban;
  vibe-kanban-pkg = vibe-kanban-flake.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  options.services.vibe-kanban = {
    enable = lib.mkEnableOption "Vibe Kanban - AI coding agent orchestration";

    package = lib.mkOption {
      type = lib.types.package;
      default = vibe-kanban-pkg;
      description = "The Vibe Kanban package to use";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port to bind the Vibe Kanban web server";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host address to bind (use 0.0.0.0 for all interfaces)";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to open the firewall for Vibe Kanban";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "kosta";
      description = "User to run Vibe Kanban as";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/home/${cfg.user}/.vibe-kanban";
      description = "Directory for Vibe Kanban data";
    };
  };

  config = lib.mkIf cfg.enable {
    # Systemd service
    systemd.services.vibe-kanban = {
      description = "Vibe Kanban - AI Coding Agent Orchestration";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      environment = {
        PORT = toString cfg.port;
        HOST = cfg.host;
        HOME = "/home/${cfg.user}";
      };

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        ExecStart = "${cfg.package}/bin/vibe-kanban";
        Restart = "on-failure";
        RestartSec = "5s";

        # Hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = [ cfg.dataDir "/home/${cfg.user}/.vibe-kanban" ];
        PrivateTmp = true;
      };
    };

    # Create data directory
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 ${cfg.user} users -"
      "d /home/${cfg.user}/.vibe-kanban 0755 ${cfg.user} users -"
    ];

    # Open firewall if requested
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

    # Also add CLI to system packages for manual use
    environment.systemPackages = [ cfg.package ];
  };
}

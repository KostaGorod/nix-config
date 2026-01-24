{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.programs.mem0;
  svcCfg = config.services.mem0;

  pkgs-unstable = import inputs.nixpkgs-unstable {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
in
{
  options.programs.mem0 = {
    enable = lib.mkEnableOption "Mem0 AI memory layer";

    enableMcpServer = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Mem0 MCP server wrapper script";
    };

    selfHosted = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use self-hosted mode with local Qdrant storage (no cloud API)";
    };

    userId = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = "Default user ID for memory operations";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "$HOME/.local/share/mem0";
      description = "Directory for Mem0 local data storage (Qdrant)";
    };
  };

  options.services.mem0 = {
    enable = lib.mkEnableOption "Mem0 MCP server as a systemd service";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8050;
      description = "Port for the Mem0 MCP SSE server";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host to bind the Mem0 server";
    };

    userId = lib.mkOption {
      type = lib.types.str;
      default = cfg.userId;
      description = "Default user ID for memory operations";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/mem0";
      description = "Directory for Mem0 data storage";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open firewall port for Mem0 service";
    };
  };

  config = lib.mkMerge [
    # programs.mem0 configuration
    (lib.mkIf cfg.enable {
      # Create necessary directories for Mem0
      systemd.tmpfiles.rules = [
        "d %h/.config/mem0 0755 - - -"
        "d %h/.cache/mem0 0755 - - -"
        "d %h/.local/share/mem0 0755 - - -"
        "d %h/.local/share/mem0/qdrant 0755 - - -"
      ];

      # Add session variables for self-hosted mode
      environment.sessionVariables = {
        MEM0_DATA_DIR = cfg.dataDir;
        MEM0_DEFAULT_USER_ID = cfg.userId;
      };

      # System packages
      environment.systemPackages = [
        pkgs-unstable.uv
      ] ++ lib.optionals cfg.enableMcpServer [
        # Wrapper script for self-hosted mem0 MCP server
        (pkgs.writeShellScriptBin "mem0-mcp-server" ''
          # Mem0 MCP Server - Self-hosted mode
          # Uses local Qdrant for vector storage

          export MEM0_DATA_DIR="''${MEM0_DATA_DIR:-$HOME/.local/share/mem0}"
          export MEM0_DEFAULT_USER_ID="''${MEM0_DEFAULT_USER_ID:-${cfg.userId}}"

          # Run mem0 MCP server via uvx
          exec ${pkgs-unstable.uv}/bin/uvx mem0-mcp "$@"
        '')
      ];
    })

    # services.mem0 configuration (systemd service)
    (lib.mkIf svcCfg.enable {
      # Ensure uv is available
      environment.systemPackages = [ pkgs-unstable.uv ];

      # Create data directory
      systemd.tmpfiles.rules = [
        "d ${svcCfg.dataDir} 0755 root root -"
        "d ${svcCfg.dataDir}/qdrant 0755 root root -"
      ];

      # Systemd service for Mem0 MCP server
      systemd.services.mem0 = {
        description = "Mem0 AI Memory MCP Server";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];

        environment = {
          MEM0_DATA_DIR = svcCfg.dataDir;
          MEM0_DEFAULT_USER_ID = svcCfg.userId;
          HOME = svcCfg.dataDir;
        };

        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs-unstable.uv}/bin/uvx mem0-mcp --transport sse --host ${svcCfg.host} --port ${toString svcCfg.port}";
          Restart = "on-failure";
          RestartSec = "5s";

          # Hardening
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [ svcCfg.dataDir ];
          PrivateTmp = true;
        };
      };

      # Firewall
      networking.firewall.allowedTCPPorts = lib.mkIf svcCfg.openFirewall [ svcCfg.port ];
    })
  ];
}

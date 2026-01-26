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
      default = "default";
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

    # Embedder configuration
    embedder = {
      provider = lib.mkOption {
        type = lib.types.enum [ "openai" "voyageai" "ollama" ];
        default = "openai";
        description = "Embedding provider (openai, voyageai, ollama)";
      };

      model = lib.mkOption {
        type = lib.types.str;
        default = "text-embedding-3-small";
        description = "Embedding model name";
      };

      apiKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to file containing the embedder API key";
      };
    };

    # LLM configuration
    llm = {
      provider = lib.mkOption {
        type = lib.types.enum [ "openai" "anthropic" "ollama" ];
        default = "openai";
        description = "LLM provider for memory extraction";
      };

      model = lib.mkOption {
        type = lib.types.str;
        default = "gpt-4.1-nano-2025-04-14";
        description = "LLM model name";
      };

      apiKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to file containing the LLM API key";
      };
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
      # Dedicated service account for mem0
      users.users.mem0 = {
        isSystemUser = true;
        group = "mem0";
        description = "Mem0 AI memory service";
      };
      users.groups.mem0 = {};

      environment.systemPackages = [ pkgs-unstable.uv ];

      systemd.tmpfiles.rules = [
        "d ${svcCfg.dataDir} 0750 mem0 mem0 -"
        "d ${svcCfg.dataDir}/qdrant 0750 mem0 mem0 -"
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
          MEM0_EMBEDDER_PROVIDER = svcCfg.embedder.provider;
          MEM0_EMBEDDER_MODEL = svcCfg.embedder.model;
          MEM0_LLM_PROVIDER = svcCfg.llm.provider;
          MEM0_LLM_MODEL = svcCfg.llm.model;
        };

        serviceConfig = {
          Type = "simple";
          Restart = "on-failure";
          RestartSec = "5s";
          User = "mem0";
          Group = "mem0";

          # Secrets via LoadCredential (not env vars) - readable at $CREDENTIALS_DIRECTORY/
          LoadCredential = lib.optionals (svcCfg.embedder.apiKeyFile != null) [
            "embedder-api-key:${svcCfg.embedder.apiKeyFile}"
          ] ++ lib.optionals (svcCfg.llm.apiKeyFile != null) [
            "llm-api-key:${svcCfg.llm.apiKeyFile}"
          ];

          # Hardening
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          ProtectClock = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          MemoryDenyWriteExecute = true;
          LockPersonality = true;
          RestrictNamespaces = true;
          RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
          ReadWritePaths = [ svcCfg.dataDir ];
          SystemCallArchitectures = "native";
          SystemCallFilter = [ "@system-service" "~@privileged" "~@resources" ];
        };

        script = let
          embedderKeyEnv = if svcCfg.embedder.provider == "voyageai" then "VOYAGE_API_KEY"
                          else if svcCfg.embedder.provider == "openai" then "OPENAI_API_KEY"
                          else "";
          llmKeyEnv = if svcCfg.llm.provider == "openai" then "OPENAI_API_KEY"
                     else if svcCfg.llm.provider == "anthropic" then "ANTHROPIC_API_KEY"
                     else "";
        in ''
          ${lib.optionalString (svcCfg.embedder.apiKeyFile != null && embedderKeyEnv != "") ''
            export ${embedderKeyEnv}="$(cat "$CREDENTIALS_DIRECTORY/embedder-api-key")"
          ''}
          ${lib.optionalString (svcCfg.llm.apiKeyFile != null && llmKeyEnv != "") ''
            export ${llmKeyEnv}="$(cat "$CREDENTIALS_DIRECTORY/llm-api-key")"
          ''}
          exec ${pkgs-unstable.uv}/bin/uvx mem0-mcp --transport sse --host ${svcCfg.host} --port ${toString svcCfg.port}
        '';
      };

      # Firewall
      networking.firewall.allowedTCPPorts = lib.mkIf svcCfg.openFirewall [ svcCfg.port ];
    })
  ];
}

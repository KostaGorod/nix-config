{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.programs.mem0;
  svcCfg = config.services.mem0;

  pkgs-unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
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
        type = lib.types.enum [
          "openai"
          "voyageai"
          "ollama"
        ];
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
        type = lib.types.enum [
          "openai"
          "anthropic"
          "ollama"
        ];
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
      ]
      ++ lib.optionals cfg.enableMcpServer [
        (pkgs.writeShellScriptBin "mem0-mcp-server" ''
          export MEM0_DATA_DIR="''${MEM0_DATA_DIR:-$HOME/.local/share/mem0}"
          export MEM0_DEFAULT_USER_ID="''${MEM0_DEFAULT_USER_ID:-${cfg.userId}}"

          exec ${pkgs-unstable.uv}/bin/uv run --with mem0ai --with "mcp[cli]" --with pydantic ${./mem0/server.py} "$@"
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
      users.groups.mem0 = { };

      environment.systemPackages = [ pkgs-unstable.uv ];

      systemd.tmpfiles.rules = [
        "d ${svcCfg.dataDir} 0750 mem0 mem0 -"
        "d ${svcCfg.dataDir}/qdrant 0750 mem0 mem0 -"
        "d ${svcCfg.dataDir}/.cache 0750 mem0 mem0 -"
        "d ${svcCfg.dataDir}/.cache/uv 0750 mem0 mem0 -"
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
          MEM0_QDRANT_PATH = "${svcCfg.dataDir}/qdrant";
          MEM0_TELEMETRY = "false";
          ANONYMIZED_TELEMETRY = "false";
        };

        serviceConfig = {
          Type = "simple";
          Restart = "on-failure";
          RestartSec = "5s";
          User = "mem0";
          Group = "mem0";

          # Note: Secrets read directly from agenix paths in script below
          # (LoadCredential requires root-readable source files, but agenix sets mem0 ownership)

          # Hardening (relaxed for Python threading/multiprocessing)
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
          # MemoryDenyWriteExecute = true;  # Breaks Python JIT/ctypes
          LockPersonality = true;
          # RestrictNamespaces = true;  # Can interfere with threading
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
          ];
          ReadWritePaths = [ svcCfg.dataDir ];
          SystemCallArchitectures = "native";
          SystemCallFilter = [
            "@system-service"
            "~@privileged"
          ]; # Removed ~@resources to allow threading
        };

        script =
          let
            embedderKeyEnv =
              if svcCfg.embedder.provider == "voyageai" then
                "VOYAGE_API_KEY"
              else if svcCfg.embedder.provider == "openai" then
                "OPENAI_API_KEY"
              else
                "";
            llmKeyEnv =
              if svcCfg.llm.provider == "openai" then
                "OPENAI_API_KEY"
              else if svcCfg.llm.provider == "anthropic" then
                "ANTHROPIC_API_KEY"
              else
                "";
          in
          ''
            ${lib.optionalString (svcCfg.embedder.apiKeyFile != null && embedderKeyEnv != "") ''
              export ${embedderKeyEnv}="$(cat "${svcCfg.embedder.apiKeyFile}")"
            ''}
            ${lib.optionalString (svcCfg.llm.apiKeyFile != null && llmKeyEnv != "") ''
              export ${llmKeyEnv}="$(cat "${svcCfg.llm.apiKeyFile}")"
            ''}
            exec ${pkgs-unstable.uv}/bin/uv run --with mem0ai --with "mcp[cli]" --with pydantic ${./mem0/server.py} --host ${svcCfg.host} --port ${toString svcCfg.port}
          '';
      };

      # Firewall
      networking.firewall.allowedTCPPorts = lib.mkIf svcCfg.openFirewall [ svcCfg.port ];
    })
  ];
}

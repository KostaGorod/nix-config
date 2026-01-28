# Simplified Mem0 configuration with external Qdrant
# - Single service definition (no dual programs/services)
# - External Qdrant for persistence and HA
# - Cleaner configuration options
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.services.mem0;

  pkgs-unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };
in
{
  options.services.mem0 = {
    enable = lib.mkEnableOption "Mem0 AI memory MCP server";

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

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open firewall port for Mem0 service";
    };

    # Qdrant configuration
    qdrant = {
      url = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:6333";
        description = "URL of the Qdrant vector database";
      };
    };

    # Embedder configuration
    embedder = {
      provider = lib.mkOption {
        type = lib.types.enum [
          "openai"
          "voyageai"
          "ollama"
        ];
        default = "voyageai";
        description = "Embedding provider";
      };

      model = lib.mkOption {
        type = lib.types.str;
        default = "voyage-4-lite";
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
        default = "anthropic";
        description = "LLM provider for memory extraction";
      };

      model = lib.mkOption {
        type = lib.types.str;
        default = "claude-sonnet-4-20250514";
        description = "LLM model name";
      };

      apiKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to file containing the LLM API key";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure uv is available for running mem0-mcp
    environment.systemPackages = [ pkgs-unstable.uv ];

    # Systemd service for Mem0 MCP server
    systemd.services.mem0 = {
      description = "Mem0 AI Memory MCP Server";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "qdrant.service"
      ];
      wants = [ "qdrant.service" ];

      environment = {
        HOME = "/var/lib/mem0";
        MEM0_DEFAULT_USER_ID = cfg.userId;
        MEM0_QDRANT_URL = cfg.qdrant.url;
        MEM0_EMBEDDER_PROVIDER = cfg.embedder.provider;
        MEM0_EMBEDDER_MODEL = cfg.embedder.model;
        MEM0_LLM_PROVIDER = cfg.llm.provider;
        MEM0_LLM_MODEL = cfg.llm.model;
      };

      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = "5s";
        StateDirectory = "mem0";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };

      script =
        let
          embedderKeyEnv =
            {
              voyageai = "VOYAGE_API_KEY";
              openai = "OPENAI_API_KEY";
              ollama = "";
            }
            .${cfg.embedder.provider};

          llmKeyEnv =
            {
              anthropic = "ANTHROPIC_API_KEY";
              openai = "OPENAI_API_KEY";
              ollama = "";
            }
            .${cfg.llm.provider};
        in
        ''
          ${lib.optionalString (cfg.embedder.apiKeyFile != null && embedderKeyEnv != "") ''
            export ${embedderKeyEnv}="$(cat ${cfg.embedder.apiKeyFile})"
          ''}
          ${lib.optionalString (cfg.llm.apiKeyFile != null && llmKeyEnv != "") ''
            export ${llmKeyEnv}="$(cat ${cfg.llm.apiKeyFile})"
          ''}
          exec ${pkgs-unstable.uv}/bin/uvx mem0-mcp --transport sse --host ${cfg.host} --port ${toString cfg.port}
        '';
    };

    # Firewall
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}

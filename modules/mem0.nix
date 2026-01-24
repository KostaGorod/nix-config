{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.programs.mem0;

  pkgs-unstable = import inputs.nixpkgs-unstable {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };

  # Python environment with mem0ai and dependencies
  mem0-python = pkgs.python312.withPackages (ps: with ps; [
    pip
  ]);
in
{
  options.programs.mem0 = {
    enable = lib.mkEnableOption "Mem0 AI memory layer";

    package = lib.mkOption {
      type = lib.types.package;
      default = mem0-python;
      description = "Python environment for Mem0";
    };

    enableMcpServer = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Mem0 MCP server for AI coding agent integration";
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

  config = lib.mkIf cfg.enable {
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

        # Run mem0 MCP server via uvx (self-hosted, no API key needed)
        exec ${pkgs-unstable.uv}/bin/uvx mem0-mcp "$@"
      '')
    ];

    # OpenCode MCP configuration for self-hosted mode:
    # Add to ~/.config/opencode/opencode.json:
    #
    # {
    #   "mcp": {
    #     "mem0": {
    #       "command": "uvx",
    #       "args": ["mem0-mcp"],
    #       "env": {
    #         "MEM0_DEFAULT_USER_ID": "kosta"
    #       }
    #     }
    #   }
    # }
    #
    # Self-hosted mode uses Qdrant with on-disk storage at ~/.local/share/mem0
    # Requires OPENAI_API_KEY for embeddings (or configure alternative LLM)
  };
}

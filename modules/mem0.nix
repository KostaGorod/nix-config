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
    # mem0ai dependencies (will be installed via pip/uv)
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

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "$HOME/.local/share/mem0";
      description = "Directory for Mem0 data storage";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create necessary directories for Mem0
    systemd.tmpfiles.rules = [
      "d %h/.config/mem0 0755 - - -"
      "d %h/.cache/mem0 0755 - - -"
      "d %h/.local/share/mem0 0755 - - -"
    ];

    # Add session variables
    environment.sessionVariables = {
      MEM0_DATA_DIR = cfg.dataDir;
    };

    # Ensure uv is available for installing mem0ai and running MCP server
    environment.systemPackages = [
      pkgs-unstable.uv
    ];

    # Create wrapper script for mem0 MCP server
    environment.systemPackages = lib.mkIf cfg.enableMcpServer [
      (pkgs.writeShellScriptBin "mem0-mcp-server" ''
        # Mem0 MCP Server wrapper
        # Requires MEM0_API_KEY environment variable for cloud mode
        # Or runs in local mode with Qdrant

        export MEM0_DATA_DIR="''${MEM0_DATA_DIR:-$HOME/.local/share/mem0}"

        # Use uvx to run mem0 MCP server
        exec ${pkgs-unstable.uv}/bin/uvx mem0-mcp "$@"
      '')
    ];

    # Add OpenCode MCP configuration hint
    # Users should add the following to their ~/.config/opencode/opencode.json:
    #
    # {
    #   "mcp": {
    #     "mem0": {
    #       "command": "uvx",
    #       "args": ["mem0-mcp"],
    #       "env": {
    #         "MEM0_API_KEY": "<your-api-key>",
    #         "MEM0_DEFAULT_USER_ID": "<your-user-id>"
    #       }
    #     }
    #   }
    # }
    #
    # For local mode (without API key), mem0 uses Qdrant with on-disk storage
  };
}

{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.programs.claude-code;

  # Import from nix-ai-tools
  nix-ai-tools = inputs.nix-ai-tools;
  claude-code-pkg = nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
in
{
  options.programs.claude-code = {
    enable = lib.mkEnableOption "Anthropic Claude Code CLI";

    package = lib.mkOption {
      type = lib.types.package;
      default = claude-code-pkg;
      description = "The Claude Code package to use";
    };
  };

  config = lib.mkIf cfg.enable {
    # Add claude-code to system packages
    environment.systemPackages = [
      cfg.package
    ];

    # Create necessary directories for Claude Code
    systemd.tmpfiles.rules = [
      "d %h/.config/claude-code 0755 - - -"
      "d %h/.cache/claude-code 0755 - - -"
      "d %h/.local/share/claude-code 0755 - - -"
    ];

    # Add session variables for users
    environment.sessionVariables = {
      CLAUDE_CODE_CONFIG_HOME = "$HOME/.config/claude-code";
      CLAUDE_CODE_CACHE_HOME = "$HOME/.cache/claude-code";
    };
  };
}
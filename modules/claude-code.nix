{ config, lib, pkgs, ... }:

{
  # Claude Code CLI development environment
  environment.systemPackages = with pkgs; [
    # Claude Code - Anthropic's official CLI for Claude
    claude-code
  ];

  # Optional: Environment variables for Claude Code
  environment.variables = {
    # Set default Claude Code configuration directory
    CLAUDE_CODE_CONFIG_HOME = "$HOME/.config/claude-code";
    # Set default cache directory
    CLAUDE_CODE_CACHE_HOME = "$HOME/.cache/claude-code";
  };

  # Create necessary directories for Claude Code
  systemd.tmpfiles.rules = [
    "d %h/.config/claude-code 0755 - - -"
    "d %h/.cache/claude-code 0755 - - -"
    "d %h/.local/share/claude-code 0755 - - -"
  ];
}
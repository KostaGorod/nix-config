{ config, lib, pkgs, ... }:

{
  # OpenCode AI development environment
  environment.systemPackages = with pkgs; [
    # OpenCode - AI coding agent for terminal
    opencode
  ];

  # Optional: Environment variables for OpenCode
  environment.variables = {
    # Set default OpenCode configuration directory
    OPENCODE_CONFIG_HOME = "$HOME/.config/opencode";
  };

  # Create necessary directories for OpenCode
  systemd.tmpfiles.rules = [
    "d %h/.config/opencode 0755 - - -"
    "d %h/.cache/opencode 0755 - - -"
  ];
}
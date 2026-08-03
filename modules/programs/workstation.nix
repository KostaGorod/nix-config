# Workstation profile
# Complete desktop environment with AI tools, productivity apps, etc.
_: {
  nixos.modules.workstation = {

    # Enable AI tools
    programs.opencode.enable = true;
    programs.claude-code.enable = true;
    programs.droids.enable = true;
    programs.bitwarden.enable = true;

    # Desktop apps
    programs.spotify-patched.enable = true;
  };
}

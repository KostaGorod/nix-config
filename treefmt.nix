# treefmt configuration for nix-config
# Run with: nix fmt
_:
{
  projectRootFile = "flake.nix";

  programs = {
    # Nix formatter (RFC-style)
    nixfmt.enable = true;

    # Dead code detection
    deadnix.enable = true;

    # Static analysis / linting
    statix.enable = true;
  };
}

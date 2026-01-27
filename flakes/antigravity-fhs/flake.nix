{
  description = "Standalone flake for Google Antigravity IDE";

  inputs = {
    # Use the community antigravity package
    antigravity-nix.url = "github:jacopone/antigravity-nix";

    # We still need nixpkgs for any additional dependencies
    nixpkgs.follows = "antigravity-nix/nixpkgs";
  };

  outputs =
    { antigravity-nix, ... }:
    let
      system = "x86_64-linux";
    in
    {
      packages.${system} = {
        # Re-export the antigravity package from the upstream flake
        inherit (antigravity-nix.packages.${system}) default;
        antigravity = antigravity-nix.packages.${system}.default;
        antigravity-fhs = antigravity-nix.packages.${system}.default;
      };

      # Also expose apps if available
      apps.${system} = antigravity-nix.apps.${system} or { };
    };
}

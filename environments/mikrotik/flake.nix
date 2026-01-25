# in flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
  outputs = { self, nixpkgs }:
    # flake-utils.lib.eachDefaultSystem
    #   (system:
        let
          # systems = ["x86_64-linux" "aarch64-darwin"];
          system = "x86_64-linux";
          pkgs = import nixpkgs {
            inherit system;
            config = {
              allowUnfree = true;
            };
          };
        in
        with pkgs;
        {
            devShells.${system}.default = mkShell {
            buildInputs = [ winbox4 ];
          };
        };
      # );
}

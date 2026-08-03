{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];

  systems = [
    "x86_64-linux"
    "aarch64-linux"
  ];

  perSystem =
    { lib, system, ... }:
    {
      treefmt = {
        projectRootFile = "flake.nix";
        settings.excludes = [ "flakes/**" ];
        programs = {
          nixfmt.enable = true;
          deadnix.enable = true;
          statix.enable = true;
        };
      };

      checks = lib.optionalAttrs (system == "x86_64-linux") {
        rocinante-toplevel = inputs.self.nixosConfigurations.rocinante.config.system.build.toplevel;
      };
    };
}

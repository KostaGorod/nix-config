{
  config,
  inputs,
  ...
}:
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

      checks = lib.mapAttrs' (
        name: _:
        lib.nameValuePair "${name}-toplevel"
          inputs.self.nixosConfigurations.${name}.config.system.build.toplevel
      ) (lib.filterAttrs (_: host: host.system == system) config.nixos.configurations);
    };
}

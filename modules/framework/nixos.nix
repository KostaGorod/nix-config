{
  config,
  inputs,
  lib,
  ...
}:
{
  options.nixos = {
    modules = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.deferredModule;
      default = { };
      description = "Composable NixOS modules.";
    };

    configurations = lib.mkOption {
      type = lib.types.lazyAttrsOf (
        lib.types.submodule {
          options = {
            system = lib.mkOption {
              type = lib.types.str;
              description = "Host system architecture.";
            };
            module = lib.mkOption {
              type = lib.types.deferredModule;
              description = "Host NixOS module.";
            };
          };
        }
      );
      default = { };
      description = "NixOS host configurations.";
    };
  };

  config.flake.nixosConfigurations = lib.mapAttrs (
    name: host:
    inputs.nixpkgs.lib.nixosSystem {
      modules = [
        {
          networking.hostName = lib.mkDefault name;
          nixpkgs.hostPlatform = host.system;
        }
        host.module
      ];
    }
  ) config.nixos.configurations;
}

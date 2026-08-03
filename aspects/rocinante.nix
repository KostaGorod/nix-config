{
  config,
  inputs,
  ...
}:
{
  nixos.configurations.rocinante = {
    system = "x86_64-linux";
    module = {
      imports = [
        ../hosts/rocinante
        ../hosts/rocinante/disko-config.nix
        inputs.disko.nixosModules.disko
        inputs.agenix.nixosModules.default
        ../modules/nixos/secrets.nix
        config.nixos.modules.workstation
        ../users/kosta
      ];
    };
  };
}

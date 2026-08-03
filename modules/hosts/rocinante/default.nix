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
        ./_hardware-configuration.nix
        ./_disko-config.nix
        inputs.disko.nixosModules.disko
        inputs.agenix.nixosModules.default
        config.nixos.modules.workstation
        config.nixos.modules.kosta
      ];
    };
  };
}

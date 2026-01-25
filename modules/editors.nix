{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # Terminal Editors
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    helix
    # Add more editors here
  ];

}

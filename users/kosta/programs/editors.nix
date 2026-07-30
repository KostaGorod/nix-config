# Editor configurations for kosta
{ pkgs, inputs, ... }:
let
  pkgs-unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };
in
{
  # VSCode with extensions
  programs.vscode = {
    package = pkgs-unstable.vscode.fhs;
    enable = true;
    extensions = with pkgs-unstable.vscode-extensions; [
      enkia.tokyo-night
      ms-vscode-remote.remote-ssh
      ms-vscode-remote.remote-ssh-edit
      github.copilot
      github.copilot-chat
      bbenoist.nix
      ms-python.python
      ms-python.debugpy
      ms-python.vscode-pylance
      ms-pyright.pyright
      ms-python.black-formatter
    ];
  };

  # Helix config via environment.etc
  environment.etc."helix/config.toml".text = ''
    theme = "tokyonight_storm"

    [editor]
    mouse = false
    line-number = "relative"
    cursor-shape.insert = "bar"

    [editor.lsp]
    display-messages = true

    [keys.normal]
    space.w = ":w"
    space.q = ":q"
  '';
}

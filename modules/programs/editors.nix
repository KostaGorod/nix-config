# Editor defaults
{ inputs, ... }:
{
  nixos.modules.workstation =
    { pkgs, ... }:
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

      environment.etc."xdg/Code/User/settings.json".text = builtins.toJSON {
        "window.titleBarStyle" = "custom";
        "workbench.colorTheme" = "Tokyo Night Storm";
      };

      environment.etc."xdg/helix/config.toml".text = ''
        theme = "tokyonight_storm"

        [editor]
        mouse = false
        line-number = "relative"
        cursor-shape.insert = "bar"

        [editor.lsp]
        display-messages = true

        [keys.normal]
        esc = ["collapse_selection", "keep_primary_selection"]
        space.w = ":w"
        space.q = ":q"
        space.space = "file_picker"
      '';
    };
}

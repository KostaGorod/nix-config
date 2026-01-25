# Editor configurations for kosta
# Helix, VSCode, Zed
{ pkgs, inputs, ... }:
let
  pkgs-unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };
in
{
  # Helix - post-modern text editor
  programs.helix = {
    enable = true;
    defaultEditor = true;
    settings = {
      theme = "tokyonight_storm";
      editor = {
        mouse = false;
        line-number = "relative";
        cursor-shape.insert = "bar";
        lsp.display-messages = true;
      };
      keys.normal = {
        space.space = "file_picker";
        space.w = ":w";
        space.q = ":q";
        esc = [
          "collapse_selection"
          "keep_primary_selection"
        ];
      };
    };
    extraPackages = with pkgs; [
      python312Packages.python-lsp-server
      nil
      yaml-language-server
      marksman
      bash-language-server
    ];
  };

  # VSCode
  programs.vscode = {
    package = pkgs-unstable.vscode.fhs;
    enable = true;
    profiles.default = {
      userSettings = {
        "window.titleBarStyle" = "custom";
        "workbench.colorTheme" = "Tokyo Night Storm";
      };
      extensions = with pkgs-unstable; [
        # Theme
        vscode-extensions.enkia.tokyo-night
        # Remote
        vscode-extensions.ms-vscode-remote.remote-ssh
        vscode-extensions.ms-vscode-remote.remote-ssh-edit
        # Copilot
        vscode-extensions.github.copilot
        vscode-extensions.github.copilot-chat
        # Nix
        vscode-extensions.bbenoist.nix
        # Python
        vscode-extensions.ms-python.python
        vscode-extensions.ms-python.debugpy
        vscode-extensions.ms-python.vscode-pylance
        vscode-extensions.ms-pyright.pyright
        vscode-extensions.ms-python.black-formatter
      ];
    };
  };

  # Zed editor extra packages
  programs.zed-editor = {
    extraPackages = [ pkgs.ansible-lint ];
  };
}

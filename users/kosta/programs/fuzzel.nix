# Fuzzel - Wayland application launcher / dmenu replacement
{ pkgs, ... }:
{
  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        font = "monospace:size=7";
        width = 100;  # wider to show more text
        lines = 15;
        horizontal-pad = 15;
        vertical-pad = 10;
        inner-pad = 5;
      };
      colors = {
        # Tokyo Night-ish theme
        background = "1a1b26ee";
        text = "c0caf5ff";
        selection = "33467cff";
        selection-text = "c0caf5ff";
        border = "7aa2f7ff";
        match = "7aa2f7ff";
      };
      border = {
        width = 2;
        radius = 8;
      };
    };
  };
}

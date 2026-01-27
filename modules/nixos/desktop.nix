# Desktop environment module
# Fonts, themes, GUI utilities, graphics
{ pkgs, inputs, ... }:
{
  # Fonts
  fonts.packages = with pkgs; [
    helvetica-neue-lt-std
    fragment-mono
    aileron
  ];

  # Desktop utilities
  environment.systemPackages = with pkgs; [
    # Themes
    numix-cursor-theme

    # GUI utilities
    gnome-calculator

    # Virtual keyboard
    maliit-keyboard
    maliit-framework

    # Graphics tools
    vulkan-tools

    # Media tools
    easyeffects

    # Python environment
    (python312.withPackages (
      ps: with ps; [
        ipython
        bpython
        requests
        pyyaml
      ]
    ))

    # CLI tools for desktop use
    sshuttle
    jqp
    jp
    httpie
    borgbackup

    # Antigravity IDE desktop entry
    (makeDesktopItem {
      name = "antigravity";
      desktopName = "Antigravity IDE";
      comment = "Google Antigravity AI-powered development environment";
      exec = "${
        inputs.antigravity-fhs.packages.${pkgs.stdenv.hostPlatform.system}.default
      }/bin/antigravity %U";
      icon = "code";
      terminal = false;
      type = "Application";
      categories = [
        "Development"
        "IDE"
      ];
    })
    (writeShellScriptBin "antigravity" ''
      exec ${
        inputs.antigravity-fhs.packages.${pkgs.stdenv.hostPlatform.system}.default
      }/bin/antigravity "$@"
    '')
  ];
}

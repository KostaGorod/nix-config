# User packages for kosta
# GUI apps, productivity tools, dev tools
{ pkgs, inputs, ... }:
let
  pkgs-unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };
in
{
  home.packages = with pkgs; [
    # IDEs & Editors
    pkgs-unstable.zed-editor
    # code-cursor

    # Browsers
    firefox
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
    (vivaldi.override {
      commandLineArgs = [
        "--ozone-platform=wayland"
        "--disable-gpu-memory-buffer-video-frames"
      ];
      proprietaryCodecs = true;
      enableWidevine = true;
    })

    # Productivity
    obsidian
    todoist-electron
    onlyoffice-desktopeditors
    _1password-gui

    # Communication
    discord
    slack

    # Terminals & Tools
    warp-terminal
    inputs.antigravity-fhs.packages.${pkgs.stdenv.hostPlatform.system}.default
    pkgs-unstable.uv
    fastfetch
    nnn
    glow
    pkgs-unstable.openterface-qt

    # Git
    git-credential-oauth

    # Kubernetes
    kubectl
    k9s
    lens

    # Remote desktop
    remmina

    # KDE integration
    kdePackages.kdeconnect-kde
    kdePackages.plasma-browser-integration

    # Media
    kdePackages.dragon
    deluge-gtk

    # System info
    pciutils

    # Nix tools
    nix-output-monitor
  ];
}

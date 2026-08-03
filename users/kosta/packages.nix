# User packages for kosta
# GUI apps, productivity tools, dev tools
{ pkgs, inputs, ... }:
let
  pkgs-unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };
  orca-ide = pkgs.callPackage ../../packages/orca-ide { };
in
{
  users.users.kosta.packages = with pkgs; [
    # IDEs & Editors
    pkgs-unstable.zed-editor
    pkgs.helix
    orca-ide
    pkgs-unstable.herdr
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
    bun
    nodejs
    mise
    pkgs-unstable.uv
    pkgs-unstable.gws
    pkgs.fuzzel
    pkgs-unstable.google-cloud-sdk
    fastfetch
    nnn
    glow

    # Kubernetes
    kubectl
    k9s
    lens

    # Remote desktop
    remmina

    # KDE integration
    kdePackages.plasma-browser-integration

    # Media
    obs-studio
    kdePackages.dragon
    deluge-gtk

    # System info
    pciutils

    # Browsers (unstable)
    pkgs-unstable.chromium

    # Git GUI
    gitkraken

    # Nix tools
    nix-output-monitor

    # Shell completions
    pkgs-unstable.carapace
  ];
}

{ config, lib, pkgs, ... }:

let
  # Create a custom derivation for OpenCode with its dependencies
  opencode-with-deps = pkgs.buildEnv {
    name = "opencode-with-deps";
    paths = with pkgs; [
      opencode
      nodejs_22
    ];
  };
in
{
  # OpenCode AI development environment
  environment.systemPackages = with pkgs; [
    # OpenCode with bundled dependencies
    opencode-with-deps

    # Required runtime dependencies
    nodejs_22
    nodePackages_latest.npm
    nodePackages_latest.pnpm
    nodePackages_latest.yarn
    nodePackages_latest.node-gyp

    # Build tools
    python3
    gcc
    gnumake

    # API and network dependencies
    curl
    wget
    cacert
    openssl

    # Optional but recommended for better functionality
    git
    ripgrep
    fd
    bat
    jq
  ];

  # Optional: Environment variables for OpenCode
  environment.variables = {
    # Set default OpenCode configuration directory
    OPENCODE_CONFIG_HOME = "$HOME/.config/opencode";
    # Node.js settings for API functionality
    NODE_OPTIONS = "--max-old-space-size=4096";
    # SSL certificates for HTTPS requests
    NODE_EXTRA_CA_CERTS = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    # Ensure npm can find global modules
    NPM_CONFIG_PREFIX = "$HOME/.npm-global";
    # Add npm global bin to PATH
    PATH = "$HOME/.npm-global/bin:$PATH";
  };

  # Create necessary directories for OpenCode
  systemd.tmpfiles.rules = [
    "d %h/.config/opencode 0755 - - -"
    "d %h/.cache/opencode 0755 - - -"
    "d %h/.local/share/opencode 0755 - - -"
    "d %h/.npm-global 0755 - - -"
  ];
}

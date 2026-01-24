# GitHub Actions Self-Hosted Runner Module
# Enables GitOps-style deployments where the node pulls and applies its own configuration
{ config, pkgs, lib, ... }:

{
  options.services.github-runner-nixos = {
    enable = lib.mkEnableOption "GitHub Actions self-hosted runner for NixOS deployments";

    url = lib.mkOption {
      type = lib.types.str;
      description = "Repository or organization URL for the runner";
      example = "https://github.com/KostaGorod/nix-config";
    };

    tokenFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to file containing the runner registration token";
      example = "/run/secrets/github-runner-token";
    };

    name = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "Name of the runner (defaults to hostname)";
    };

    labels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "nixos" "self-hosted" ];
      description = "Labels for the runner";
    };
  };

  config = lib.mkIf config.services.github-runner-nixos.enable {
    # GitHub Actions runner service
    services.github-runners.${config.services.github-runner-nixos.name} = {
      enable = true;
      url = config.services.github-runner-nixos.url;
      tokenFile = config.services.github-runner-nixos.tokenFile;
      name = config.services.github-runner-nixos.name;
      extraLabels = config.services.github-runner-nixos.labels ++ [
        config.networking.hostName
        "linux"
        "x64"
      ];

      # Run in ephemeral mode - clean state for each job
      ephemeral = true;

      # Replace existing runner with same name on registration
      replace = true;

      # Extra packages available to the runner
      extraPackages = with pkgs; [
        git
        nix
        nixos-rebuild
        bash
        coreutils
        curl
        jq
      ];

      # Service configuration
      serviceOverrides = {
        # Restart on failure with backoff
        Restart = "always";
        RestartSec = "5s";
      };
    };

    # Ensure the runner user can run nixos-rebuild
    security.sudo.extraRules = [
      {
        users = [ "github-runner-${config.services.github-runner-nixos.name}" ];
        commands = [
          {
            command = "${pkgs.nixos-rebuild}/bin/nixos-rebuild";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/run/current-system/sw/bin/nixos-rebuild";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    # Nix settings for the runner
    nix.settings.trusted-users = [
      "github-runner-${config.services.github-runner-nixos.name}"
    ];
  };
}

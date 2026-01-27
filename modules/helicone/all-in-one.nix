# Helicone All-in-One - Minimal deployment for testing
# Usage: Import this module and set services.helicone-aio.enable = true
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.helicone-aio;
  garagePort = 3900;  # Garage S3 API port
in {
  options.services.helicone-aio = {
    enable = mkEnableOption "Helicone All-in-One container";

    port = mkOption {
      type = types.port;
      default = 3000;
      description = "Port for Helicone web UI";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/helicone";
      description = "Data directory for persistent storage";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open firewall for Helicone port";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Address to listen on (0.0.0.0 for all interfaces)";
    };

    hostName = mkOption {
      type = types.str;
      default = "localhost";
      description = "Hostname or IP for self-hosted URLs (e.g., gpu-node-1, 192.168.1.10)";
    };

    useGarage = mkOption {
      type = types.bool;
      default = false;
      description = "Use native NixOS Garage for S3 instead of container's MinIO";
    };

    garage = {
      rpcSecretFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "File containing RPC secret for Garage (32-byte hex). Generate with: openssl rand -hex 32";
      };

      s3AccessKey = mkOption {
        type = types.str;
        default = "helicone";
        description = "S3 access key for Helicone bucket";
      };

      s3SecretKeyFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "File containing S3 secret key";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # Base configuration
    {
      virtualisation.docker.enable = true;

      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0755 root root -"
        "d ${cfg.dataDir}/postgres 0755 root root -"
        "d ${cfg.dataDir}/clickhouse 0755 root root -"
      ] ++ (if cfg.useGarage then [
        "d ${cfg.dataDir}/garage 0755 root root -"
        "d ${cfg.dataDir}/garage/meta 0755 root root -"
        "d ${cfg.dataDir}/garage/data 0755 root root -"
      ] else [
        "d ${cfg.dataDir}/minio 0755 root root -"
      ]);

      virtualisation.oci-containers.containers.helicone = {
        image = "helicone/helicone-all-in-one:latest";

        ports = [
          "${cfg.listenAddress}:${toString cfg.port}:3000"
          "${cfg.listenAddress}:8585:8585"
        ] ++ (if cfg.useGarage then [] else [
          "${cfg.listenAddress}:9080:9080"  # Only expose MinIO if not using Garage
        ]);

        volumes = [
          "${cfg.dataDir}/postgres:/var/lib/postgresql/data"
          "${cfg.dataDir}/clickhouse:/var/lib/clickhouse"
        ] ++ (if cfg.useGarage then [] else [
          "${cfg.dataDir}/minio:/data"
        ]);

        environment = {
          NEXT_PUBLIC_IS_ON_PREM = "true";
          NEXT_PUBLIC_APP_URL = "http://${cfg.hostName}:${toString cfg.port}";
          NEXT_PUBLIC_HELICONE_JAWN_SERVICE = "http://${cfg.hostName}:8585";
          SITE_URL = "http://${cfg.hostName}:${toString cfg.port}";
          BETTER_AUTH_URL = "http://${cfg.hostName}:${toString cfg.port}";
          BETTER_AUTH_SECRET = "test-secret-change-me-in-production";
          # S3 endpoint - either Garage or internal MinIO
          S3_ENDPOINT = if cfg.useGarage
            then "http://${cfg.hostName}:${toString garagePort}"
            else "http://${cfg.hostName}:9080";
          S3_REGION = "garage";
          S3_BUCKET = "helicone";
        } // (if cfg.useGarage then {
          S3_ACCESS_KEY = cfg.garage.s3AccessKey;
          # Note: S3_SECRET_KEY should be set via environmentFiles for security
        } else {});

        # For Garage, pass secret key via environment file
        environmentFiles = mkIf (cfg.useGarage && cfg.garage.s3SecretKeyFile != null) [
          cfg.garage.s3SecretKeyFile
        ];
      };

      networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall (
        [ cfg.port 8585 ] ++ (if cfg.useGarage then [ garagePort ] else [ 9080 ])
      );
    }

    # Garage configuration (when enabled)
    (mkIf cfg.useGarage {
      services.garage = {
        enable = true;
        package = pkgs.garage;

        settings = {
          metadata_dir = "${cfg.dataDir}/garage/meta";
          data_dir = "${cfg.dataDir}/garage/data";

          replication_mode = "none";  # Single node

          rpc_bind_addr = "[::]:3901";
          rpc_public_addr = "127.0.0.1:3901";

          s3_api = {
            s3_region = "garage";
            api_bind_addr = "[::]:${toString garagePort}";
            root_domain = ".s3.${cfg.hostName}";
          };

          s3_web = {
            bind_addr = "[::]:3902";
            root_domain = ".web.${cfg.hostName}";
          };

          admin = {
            api_bind_addr = "[::]:3903";
          };
        };

        environmentFile = cfg.garage.rpcSecretFile;
      };

      # Ensure Garage starts before Helicone container
      systemd.services.podman-helicone = {
        after = [ "garage.service" ];
        requires = [ "garage.service" ];
      };
    })
  ]);
}

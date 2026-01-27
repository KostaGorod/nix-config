# Qdrant Vector Database - NixOS module
# Runs Qdrant as an OCI container for mem0 and other vector storage needs
# Supports single-node and cluster mode for HA
{ config, lib, pkgs, ... }:

let
  cfg = config.services.qdrant;
in
{
  options.services.qdrant = {
    enable = lib.mkEnableOption "Qdrant vector database";

    port = lib.mkOption {
      type = lib.types.port;
      default = 6333;
      description = "HTTP API port";
    };

    grpcPort = lib.mkOption {
      type = lib.types.port;
      default = 6334;
      description = "gRPC API port";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host to bind Qdrant";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/qdrant";
      description = "Data directory for persistent storage";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open firewall for Qdrant ports";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/qdrant/qdrant:v1.13.2";
      description = "Qdrant container image";
    };

    # Cluster mode for HA (future use)
    cluster = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable cluster mode for HA";
      };

      bootstrapPeer = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Bootstrap peer URL for joining cluster (e.g., http://qdrant-node-1:6335)";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Use podman for containers (consistent with helicone module)
    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
    };

    # Create data directory
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
      "d ${cfg.dataDir}/storage 0755 root root -"
      "d ${cfg.dataDir}/snapshots 0755 root root -"
    ];

    # Qdrant container
    virtualisation.oci-containers.containers.qdrant = {
      image = cfg.image;
      autoStart = true;

      ports = [
        "${cfg.host}:${toString cfg.port}:6333"
        "${cfg.host}:${toString cfg.grpcPort}:6334"
      ];

      volumes = [
        "${cfg.dataDir}/storage:/qdrant/storage:rw"
        "${cfg.dataDir}/snapshots:/qdrant/snapshots:rw"
      ];

      environment = {
        QDRANT__SERVICE__HTTP_PORT = "6333";
        QDRANT__SERVICE__GRPC_PORT = "6334";
      } // lib.optionalAttrs cfg.cluster.enable {
        QDRANT__CLUSTER__ENABLED = "true";
        QDRANT__CLUSTER__P2P__PORT = "6335";
      } // lib.optionalAttrs (cfg.cluster.bootstrapPeer != null) {
        QDRANT__CLUSTER__BOOTSTRAP = cfg.cluster.bootstrapPeer;
      };

      extraOptions = [
        "--health-cmd=wget --no-verbose --tries=1 --spider http://localhost:6333/health || exit 1"
        "--health-interval=30s"
        "--health-timeout=10s"
        "--health-retries=3"
      ];
    };

    # Firewall
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
      cfg.port
      cfg.grpcPort
    ];
  };
}

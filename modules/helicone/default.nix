{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.helicone;

  # Generate ClickHouse user XML
  clickhouseUserXml = ''
    <clickhouse>
      <users>
        <${cfg.clickhouse.user}>
          <password>${cfg.clickhouse.password}</password>
          <networks><ip>::/0</ip></networks>
          <profile>default</profile>
          <quota>default</quota>
        </${cfg.clickhouse.user}>
      </users>
    </clickhouse>
  '';

  # Garage settings for S3
  garageSettings = {
    metadata_dir = "/var/lib/garage/meta";
    data_dir = "/var/lib/garage/data";
    db_engine = "lmdb";
    replication_factor = 1;

    rpc_bind_addr = "[::]:3901";
    rpc_public_addr = "127.0.0.1:3901";
    rpc_secret = cfg.s3.garage.rpcSecret;

    s3_api = {
      s3_region = "garage";
      api_bind_addr = "[::]:${toString cfg.s3.port}";
      root_domain = ".s3.garage.localhost";
    };

    admin = {
      api_bind_addr = "[::]:3903";
      admin_token = cfg.s3.garage.adminToken;
    };
  };

in {
  options.services.helicone = {
    enable = mkEnableOption "Helicone LLM observability platform";

    deploymentMode = mkOption {
      type = types.enum [ "all-in-one" "hybrid" ];
      default = "all-in-one";
      description = ''
        Deployment mode:
        - all-in-one: Single container with all services bundled
        - hybrid: Native NixOS databases with Helicone app container
      '';
    };

    domain = mkOption {
      type = types.str;
      default = "helicone.localhost";
      description = "Domain for Helicone dashboard";
    };

    port = mkOption {
      type = types.port;
      default = 3000;
      description = "Port for Helicone web UI";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/helicone";
      description = "Directory for Helicone data";
    };

    image = mkOption {
      type = types.str;
      default = "helicone/helicone-all-in-one:latest";
      description = "Docker image for Helicone";
    };

    authSecret = mkOption {
      type = types.str;
      default = "";
      description = "Better Auth secret (generate with: openssl rand -base64 32)";
    };

    authSecretFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "File containing Better Auth secret";
    };

    # PostgreSQL options (hybrid mode)
    postgresql = {
      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "PostgreSQL host";
      };

      port = mkOption {
        type = types.port;
        default = 5432;
        description = "PostgreSQL port";
      };

      database = mkOption {
        type = types.str;
        default = "helicone";
        description = "PostgreSQL database name";
      };

      user = mkOption {
        type = types.str;
        default = "helicone";
        description = "PostgreSQL user";
      };

      password = mkOption {
        type = types.str;
        default = "helicone";
        description = "PostgreSQL password (use passwordFile in production)";
      };

      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "File containing PostgreSQL password";
      };
    };

    # ClickHouse options (hybrid mode)
    clickhouse = {
      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "ClickHouse host";
      };

      port = mkOption {
        type = types.port;
        default = 8123;
        description = "ClickHouse HTTP port";
      };

      user = mkOption {
        type = types.str;
        default = "helicone";
        description = "ClickHouse user";
      };

      password = mkOption {
        type = types.str;
        default = "helicone";
        description = "ClickHouse password";
      };
    };

    # S3 options
    s3 = {
      backend = mkOption {
        type = types.enum [ "embedded" "garage" "rustfs" "minio" "external" ];
        default = "embedded";
        description = ''
          S3 backend:
          - embedded: Use MinIO inside all-in-one container
          - garage: Native NixOS Garage service
          - rustfs: RustFS container
          - minio: Native NixOS MinIO service
          - external: External S3-compatible endpoint
        '';
      };

      endpoint = mkOption {
        type = types.str;
        default = "http://127.0.0.1:3900";
        description = "S3 endpoint URL";
      };

      port = mkOption {
        type = types.port;
        default = 3900;
        description = "S3 API port";
      };

      accessKey = mkOption {
        type = types.str;
        default = "";
        description = "S3 access key";
      };

      secretKey = mkOption {
        type = types.str;
        default = "";
        description = "S3 secret key";
      };

      bucket = mkOption {
        type = types.str;
        default = "request-response-logs";
        description = "S3 bucket name";
      };

      region = mkOption {
        type = types.str;
        default = "garage";
        description = "S3 region";
      };

      garage = {
        rpcSecret = mkOption {
          type = types.str;
          default = "";
          description = "Garage RPC secret (generate with: openssl rand -hex 32)";
        };

        adminToken = mkOption {
          type = types.str;
          default = "";
          description = "Garage admin token";
        };
      };
    };

    # CLIProxyAPI integration
    cliproxyapi = {
      enable = mkEnableOption "CLIProxyAPI OAuth proxy integration";

      image = mkOption {
        type = types.str;
        default = "ghcr.io/router-for-me/cliproxyapi:latest";
        description = "CLIProxyAPI Docker image";
      };

      port = mkOption {
        type = types.port;
        default = 8080;
        description = "CLIProxyAPI API port";
      };

      managementPort = mkOption {
        type = types.port;
        default = 8081;
        description = "CLIProxyAPI management API port";
      };

      dataDir = mkOption {
        type = types.path;
        default = "/var/lib/cliproxyapi";
        description = "CLIProxyAPI data directory";
      };
    };

    # AI Gateway
    aiGateway = {
      enable = mkEnableOption "Helicone AI Gateway";

      port = mkOption {
        type = types.port;
        default = 8787;
        description = "AI Gateway port";
      };
    };

    # Nginx
    nginx = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Nginx reverse proxy";
      };

      enableSSL = mkOption {
        type = types.bool;
        default = false;
        description = "Enable SSL with ACME";
      };
    };

    # Firewall
    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open firewall ports";
    };

    # Backup configuration
    backup = {
      enable = mkEnableOption "automated backups for Helicone databases";

      backend = mkOption {
        type = types.enum [ "restic" "borgbackup" ];
        default = "restic";
        description = "Backup tool to use";
      };

      repository = mkOption {
        type = types.str;
        default = "s3:http://localhost:3900/backups";
        description = "Backup repository URL (restic format)";
      };

      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "File containing backup repository password";
      };

      environmentFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "File containing environment variables (S3 credentials, etc.)";
      };

      schedule = mkOption {
        type = types.str;
        default = "daily";
        description = "Backup schedule (systemd calendar format)";
      };

      retention = {
        daily = mkOption {
          type = types.int;
          default = 7;
          description = "Number of daily backups to keep";
        };

        weekly = mkOption {
          type = types.int;
          default = 4;
          description = "Number of weekly backups to keep";
        };

        monthly = mkOption {
          type = types.int;
          default = 6;
          description = "Number of monthly backups to keep";
        };
      };

      notify = {
        onFailure = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Webhook URL to notify on backup failure";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    # Assertions
    assertions = [
      {
        assertion = cfg.authSecret != "" || cfg.authSecretFile != null;
        message = "services.helicone.authSecret or authSecretFile must be set";
      }
      {
        assertion = cfg.deploymentMode == "all-in-one" || cfg.s3.backend != "embedded";
        message = "Hybrid mode requires an external S3 backend (garage, rustfs, minio, or external)";
      }
      {
        assertion = cfg.s3.backend != "garage" || (cfg.s3.garage.rpcSecret != "" && cfg.s3.garage.adminToken != "");
        message = "Garage backend requires rpcSecret and adminToken to be set";
      }
    ];

    # Docker/Podman
    virtualisation.docker.enable = true;

    # Create data directories
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root -"
      "d ${cfg.dataDir}/postgres 0750 root root -"
      "d ${cfg.dataDir}/clickhouse 0750 root root -"
      "d ${cfg.dataDir}/minio 0750 root root -"
    ] ++ optionals cfg.cliproxyapi.enable [
      "d ${cfg.cliproxyapi.dataDir} 0750 root root -"
      "d ${cfg.cliproxyapi.dataDir}/config 0750 root root -"
      "d ${cfg.cliproxyapi.dataDir}/data 0750 root root -"
    ];

    # === ALL-IN-ONE MODE ===
    virtualisation.oci-containers.containers = mkMerge [
      # Helicone all-in-one container
      (mkIf (cfg.deploymentMode == "all-in-one") {
        helicone = {
          image = cfg.image;
          ports = [ "127.0.0.1:${toString cfg.port}:3000" ];

          volumes = [
            "${cfg.dataDir}/postgres:/var/lib/postgresql/data"
            "${cfg.dataDir}/clickhouse:/var/lib/clickhouse"
            "${cfg.dataDir}/minio:/data"
          ];

          environment = {
            BETTER_AUTH_SECRET = cfg.authSecret;
          };

          environmentFiles = optional (cfg.authSecretFile != null) cfg.authSecretFile;
        };
      })

      # Helicone container for hybrid mode (connects to external DBs)
      (mkIf (cfg.deploymentMode == "hybrid") {
        helicone = {
          image = cfg.image;
          ports = [ "127.0.0.1:${toString cfg.port}:3000" ];

          environment = {
            # External PostgreSQL
            DATABASE_URL = "postgresql://${cfg.postgresql.user}:${cfg.postgresql.password}@host.containers.internal:${toString cfg.postgresql.port}/${cfg.postgresql.database}";

            # External ClickHouse
            CLICKHOUSE_HOST = "host.containers.internal";
            CLICKHOUSE_PORT = toString cfg.clickhouse.port;
            CLICKHOUSE_USER = cfg.clickhouse.user;
            CLICKHOUSE_PASSWORD = cfg.clickhouse.password;

            # External S3
            S3_ENDPOINT = "http://host.containers.internal:${toString cfg.s3.port}";
            S3_ACCESS_KEY = cfg.s3.accessKey;
            S3_SECRET_KEY = cfg.s3.secretKey;
            S3_BUCKET_NAME = cfg.s3.bucket;
            S3_REGION = cfg.s3.region;

            BETTER_AUTH_SECRET = cfg.authSecret;
          };

          environmentFiles = optional (cfg.authSecretFile != null) cfg.authSecretFile;

          extraOptions = [
            "--add-host=host.containers.internal:host-gateway"
          ];
        };
      })

      # CLIProxyAPI container
      (mkIf cfg.cliproxyapi.enable {
        cliproxyapi = {
          image = cfg.cliproxyapi.image;
          ports = [
            "127.0.0.1:${toString cfg.cliproxyapi.port}:8080"
            "127.0.0.1:${toString cfg.cliproxyapi.managementPort}:8081"
          ];

          volumes = [
            "${cfg.cliproxyapi.dataDir}/config:/app/config"
            "${cfg.cliproxyapi.dataDir}/data:/app/data"
          ];

          environment = {
            MANAGEMENT_API_ENABLED = "true";
            MANAGEMENT_API_PORT = "8081";
          };

          extraOptions = [
            "--add-host=host.containers.internal:host-gateway"
          ];
        };
      })

      # RustFS container (if selected)
      (mkIf (cfg.s3.backend == "rustfs") {
        rustfs = {
          image = "rustfs/rustfs:latest";
          ports = [
            "127.0.0.1:${toString cfg.s3.port}:9000"
            "127.0.0.1:9001:9001"
          ];
          volumes = [
            "/var/lib/rustfs:/data"
          ];
          environment = {
            RUSTFS_ROOT_USER = cfg.s3.accessKey;
            RUSTFS_ROOT_PASSWORD = cfg.s3.secretKey;
          };
          cmd = [ "server" "/data" "--console-address" ":9001" ];
        };
      })
    ];

    # === HYBRID MODE NATIVE SERVICES ===

    # PostgreSQL
    services.postgresql = mkIf (cfg.deploymentMode == "hybrid") {
      enable = true;
      package = pkgs.postgresql_17;
      enableTCPIP = true;

      settings = {
        max_connections = 200;
        shared_buffers = "256MB";
        effective_cache_size = "1GB";
      };

      ensureDatabases = [ cfg.postgresql.database ];
      ensureUsers = [{
        name = cfg.postgresql.user;
        ensureDBOwnership = true;
      }];

      authentication = ''
        host ${cfg.postgresql.database} ${cfg.postgresql.user} 127.0.0.1/32 scram-sha-256
        host ${cfg.postgresql.database} ${cfg.postgresql.user} 172.17.0.0/16 scram-sha-256
      '';

      initialScript = pkgs.writeText "helicone-init.sql" ''
        ALTER USER ${cfg.postgresql.user} WITH PASSWORD '${cfg.postgresql.password}';
      '';
    };

    # ClickHouse
    services.clickhouse = mkIf (cfg.deploymentMode == "hybrid") {
      enable = true;
      package = pkgs.clickhouse;
    };

    environment.etc = mkIf (cfg.deploymentMode == "hybrid") {
      "clickhouse-server/users.d/helicone.xml".text = clickhouseUserXml;
    };

    # Garage S3
    services.garage = mkIf (cfg.deploymentMode == "hybrid" && cfg.s3.backend == "garage") {
      enable = true;
      package = pkgs.garage;
      settings = garageSettings;
    };

    # Garage bucket initialization
    systemd.services.garage-helicone-init = mkIf (cfg.deploymentMode == "hybrid" && cfg.s3.backend == "garage") {
      description = "Initialize Garage buckets for Helicone";
      after = [ "garage.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      path = [ pkgs.garage ];

      script = ''
        # Wait for Garage to be ready
        sleep 10

        # Create access key for Helicone
        garage key create helicone-key || true

        # Create buckets
        garage bucket create ${cfg.s3.bucket} || true
        garage bucket create prompts || true
        garage bucket create hql || true
        garage bucket create llm-cache || true

        # Grant permissions
        garage bucket allow --read --write --owner ${cfg.s3.bucket} --key helicone-key || true
        garage bucket allow --read --write --owner prompts --key helicone-key || true
        garage bucket allow --read --write --owner hql --key helicone-key || true
        garage bucket allow --read --write --owner llm-cache --key helicone-key || true

        # Output key info for configuration
        garage key info helicone-key
      '';
    };

    # MinIO
    services.minio = mkIf (cfg.deploymentMode == "hybrid" && cfg.s3.backend == "minio") {
      enable = true;
      dataDir = [ "/var/lib/minio/data" ];
      listenAddress = ":${toString cfg.s3.port}";
      consoleAddress = ":9001";
    };

    # === NGINX ===
    services.nginx = mkIf cfg.nginx.enable {
      enable = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = cfg.nginx.enableSSL;
      recommendedGzipSettings = true;

      virtualHosts.${cfg.domain} = {
        forceSSL = cfg.nginx.enableSSL;
        enableACME = cfg.nginx.enableSSL;

        locations = {
          "/" = {
            proxyPass = "http://127.0.0.1:${toString cfg.port}";
            proxyWebsockets = true;
          };
        } // optionalAttrs cfg.aiGateway.enable {
          "/v1" = {
            proxyPass = "http://127.0.0.1:${toString cfg.aiGateway.port}";
            extraConfig = ''
              proxy_read_timeout 300s;
              proxy_send_timeout 300s;
            '';
          };
        } // optionalAttrs cfg.cliproxyapi.enable {
          "/proxy-admin" = {
            proxyPass = "http://127.0.0.1:${toString cfg.cliproxyapi.managementPort}";
            extraConfig = ''
              allow 127.0.0.1;
              allow 10.0.0.0/8;
              deny all;
            '';
          };
        };
      };
    };

    # === FIREWALL ===
    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall (
      [ 80 ]
      ++ optional cfg.nginx.enableSSL 443
    );

    # === BACKUPS ===

    # Backup directories
    systemd.tmpfiles.rules = mkIf cfg.backup.enable [
      "d /var/backup/helicone 0750 root root -"
      "d /var/backup/helicone/postgresql 0750 postgres postgres -"
      "d /var/backup/helicone/clickhouse 0750 clickhouse clickhouse -"
    ];

    # Restic backups
    services.restic.backups = mkIf (cfg.backup.enable && cfg.backup.backend == "restic") {
      # PostgreSQL backup
      helicone-postgresql = mkIf (cfg.deploymentMode == "hybrid") {
        initialize = true;
        repository = "${cfg.backup.repository}/postgresql";
        passwordFile = cfg.backup.passwordFile;
        environmentFile = cfg.backup.environmentFile;

        backupPrepareCommand = ''
          ${pkgs.sudo}/bin/sudo -u postgres ${pkgs.postgresql}/bin/pg_dumpall \
            --clean --if-exists \
            > /var/backup/helicone/postgresql/dump.sql
        '';

        paths = [ "/var/backup/helicone/postgresql" ];

        pruneOpts = [
          "--keep-daily ${toString cfg.backup.retention.daily}"
          "--keep-weekly ${toString cfg.backup.retention.weekly}"
          "--keep-monthly ${toString cfg.backup.retention.monthly}"
        ];

        timerConfig = {
          OnCalendar = cfg.backup.schedule;
          Persistent = true;
          RandomizedDelaySec = "30min";
        };
      };

      # ClickHouse backup
      helicone-clickhouse = mkIf (cfg.deploymentMode == "hybrid") {
        initialize = true;
        repository = "${cfg.backup.repository}/clickhouse";
        passwordFile = cfg.backup.passwordFile;
        environmentFile = cfg.backup.environmentFile;

        backupPrepareCommand = ''
          ${pkgs.clickhouse}/bin/clickhouse-client --query "SYSTEM STOP MERGES" || true
          ${pkgs.clickhouse}/bin/clickhouse-client --query "SYSTEM FLUSH LOGS" || true
          sync
        '';

        backupCleanupCommand = ''
          ${pkgs.clickhouse}/bin/clickhouse-client --query "SYSTEM START MERGES" || true
        '';

        paths = [ "/var/lib/clickhouse" ];

        exclude = [
          "/var/lib/clickhouse/preprocessed_configs"
          "/var/lib/clickhouse/status"
        ];

        pruneOpts = [
          "--keep-daily ${toString cfg.backup.retention.daily}"
          "--keep-weekly ${toString cfg.backup.retention.weekly}"
          "--keep-monthly ${toString cfg.backup.retention.monthly}"
        ];

        timerConfig = {
          OnCalendar = cfg.backup.schedule;
          Persistent = true;
          RandomizedDelaySec = "30min";
        };
      };

      # Garage/S3 data backup
      helicone-s3 = mkIf (cfg.deploymentMode == "hybrid" && cfg.s3.backend == "garage") {
        initialize = true;
        repository = "${cfg.backup.repository}/garage";
        passwordFile = cfg.backup.passwordFile;
        environmentFile = cfg.backup.environmentFile;

        paths = [ "/var/lib/garage/data" ];
        exclude = [ "/var/lib/garage/meta" ];

        pruneOpts = [
          "--keep-daily ${toString cfg.backup.retention.daily}"
          "--keep-weekly ${toString cfg.backup.retention.weekly}"
        ];

        timerConfig = {
          OnCalendar = cfg.backup.schedule;
          Persistent = true;
          RandomizedDelaySec = "30min";
        };
      };
    };

    # BorgBackup alternative
    services.borgbackup.jobs = mkIf (cfg.backup.enable && cfg.backup.backend == "borgbackup") {
      helicone-postgresql = mkIf (cfg.deploymentMode == "hybrid") {
        paths = [ "/var/backup/helicone/postgresql" ];
        repo = cfg.backup.repository;
        encryption.mode = "none";  # Use passCommand with sops for encryption

        preHook = ''
          ${pkgs.sudo}/bin/sudo -u postgres ${pkgs.postgresql}/bin/pg_dumpall \
            --clean --if-exists \
            > /var/backup/helicone/postgresql/dump.sql
        '';

        compression = "zstd,3";
        startAt = cfg.backup.schedule;

        prune.keep = {
          daily = cfg.backup.retention.daily;
          weekly = cfg.backup.retention.weekly;
          monthly = cfg.backup.retention.monthly;
        };
      };

      helicone-clickhouse = mkIf (cfg.deploymentMode == "hybrid") {
        paths = [ "/var/lib/clickhouse" ];
        repo = cfg.backup.repository;
        encryption.mode = "none";

        preHook = ''
          ${pkgs.clickhouse}/bin/clickhouse-client --query "SYSTEM STOP MERGES" || true
          ${pkgs.clickhouse}/bin/clickhouse-client --query "SYSTEM FLUSH LOGS" || true
        '';

        postHook = ''
          ${pkgs.clickhouse}/bin/clickhouse-client --query "SYSTEM START MERGES" || true
        '';

        compression = "zstd,3";
        startAt = cfg.backup.schedule;

        prune.keep = {
          daily = cfg.backup.retention.daily;
          weekly = cfg.backup.retention.weekly;
          monthly = cfg.backup.retention.monthly;
        };
      };
    };

    # Backup failure notification
    systemd.services = mkIf (cfg.backup.enable && cfg.backup.notify.onFailure != null) {
      "backup-alert@" = {
        description = "Backup failure alert for %i";
        serviceConfig.Type = "oneshot";
        script = ''
          ${pkgs.curl}/bin/curl -X POST \
            -H "Content-Type: application/json" \
            -d '{"text": "🚨 Helicone backup failed: %i on ${config.networking.hostName}"}' \
            "${cfg.backup.notify.onFailure}"
        '';
      };
    };
  };
}

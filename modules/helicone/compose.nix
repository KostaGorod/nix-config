# Helicone LLM Observability - NixOS native deployment
# Uses oci-containers with proper service definitions
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.helicone;

  # Container network name
  networkName = "helicone";

  # Internal hostnames for container networking
  dbHost = "helicone-db";
  clickhouseHost = "helicone-clickhouse";
  minioHost = "helicone-minio";
  redisHost = "helicone-redis";
  jawnHost = "helicone-jawn";

in {
  options.services.helicone = {
    enable = mkEnableOption "Helicone LLM Observability";

    hostName = mkOption {
      type = types.str;
      default = "localhost";
      description = "External hostname for self-hosted URLs";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/helicone";
      description = "Data directory for persistent storage";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open firewall for Helicone ports";
    };

    ports = {
      web = mkOption {
        type = types.port;
        default = 3000;
        description = "Web UI port";
      };
      jawn = mkOption {
        type = types.port;
        default = 8585;
        description = "Jawn API port";
      };
      minio = mkOption {
        type = types.port;
        default = 9080;
        description = "MinIO S3 API port (for browser access to request/response bodies)";
      };
      minioConsole = mkOption {
        type = types.port;
        default = 9001;
        description = "MinIO Console/Dashboard port";
      };
    };

    secrets = {
      betterAuthSecret = mkOption {
        type = types.str;
        default = "change-me-generate-with-openssl-rand-hex-32";
        description = "Better Auth secret";
      };
      postgresPassword = mkOption {
        type = types.str;
        default = "helicone";
        description = "PostgreSQL password";
      };
      s3AccessKey = mkOption {
        type = types.str;
        default = "helicone";
        description = "S3/MinIO access key";
      };
      s3SecretKey = mkOption {
        type = types.str;
        default = "helicone123";
        description = "S3/MinIO secret key (min 8 chars)";
      };
    };

    images = {
      postgres = mkOption {
        type = types.str;
        default = "postgres:17.4-alpine";
        description = "PostgreSQL image";
      };
      clickhouse = mkOption {
        type = types.str;
        default = "clickhouse/clickhouse-server:24.3.13.40-alpine";
        description = "ClickHouse image";
      };
      minio = mkOption {
        type = types.str;
        default = "minio/minio:latest";
        description = "MinIO image";
      };
      redis = mkOption {
        type = types.str;
        default = "redis:8.0-alpine";
        description = "Redis image";
      };
      jawn = mkOption {
        type = types.str;
        default = "helicone/jawn:latest";
        description = "Helicone Jawn image";
      };
      web = mkOption {
        type = types.str;
        default = "helicone/web:latest";
        description = "Helicone Web image";
      };
    };
  };

  config = mkIf cfg.enable {
    # Use podman for containers
    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };

    # Create data directories
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
      "d ${cfg.dataDir}/postgres 0755 999 999 -"
      "d ${cfg.dataDir}/clickhouse 0755 101 101 -"
      "d ${cfg.dataDir}/minio 0755 root root -"
      "d ${cfg.dataDir}/redis 0755 999 999 -"
    ];

    # Create podman network for inter-container communication
    systemd.services.helicone-network = {
      description = "Create Helicone podman network";
      wantedBy = [ "multi-user.target" ];
      before = [
        "podman-helicone-db.service"
        "podman-helicone-clickhouse.service"
        "podman-helicone-minio.service"
        "podman-helicone-redis.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.podman}/bin/podman network create ${networkName} --ignore";
        ExecStop = "${pkgs.podman}/bin/podman network rm ${networkName} --ignore";
      };
    };

    # Database migrations - run once after PostgreSQL is ready
    systemd.services.helicone-migrate = {
      description = "Run Helicone database migrations";
      wantedBy = [ "multi-user.target" ];
      after = [ "podman-helicone-db.service" ];
      before = [ "podman-helicone-jawn.service" "podman-helicone-web.service" ];
      requires = [ "podman-helicone-db.service" ];

      path = [ pkgs.git pkgs.podman ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "5min";
      };

      script = ''
        set -e
        MIGRATIONS_DIR="${cfg.dataDir}/migrations"
        MERGED_DIR="$MIGRATIONS_DIR/merged"

        # Clone/update Helicone repo for migrations
        if [ ! -d "$MIGRATIONS_DIR/helicone" ]; then
          echo "Cloning Helicone repo for migrations..."
          mkdir -p "$MIGRATIONS_DIR"
          git clone --depth 1 --sparse https://github.com/Helicone/helicone.git "$MIGRATIONS_DIR/helicone"
          cd "$MIGRATIONS_DIR/helicone"
          git sparse-checkout set supabase/migrations supabase/migrations_without_supabase
        else
          echo "Updating migrations..."
          cd "$MIGRATIONS_DIR/helicone"
          git pull origin main || true
        fi

        # Merge migrations from both folders
        # migrations_without_supabase provides auth stubs that main migrations need
        # Version numbers are designed to interleave correctly
        echo "Merging migration folders..."
        rm -rf "$MERGED_DIR"
        mkdir -p "$MERGED_DIR"
        cp "$MIGRATIONS_DIR/helicone/supabase/migrations_without_supabase"/*.sql "$MERGED_DIR/" 2>/dev/null || true
        cp "$MIGRATIONS_DIR/helicone/supabase/migrations"/*.sql "$MERGED_DIR/" 2>/dev/null || true
        echo "Total migrations: $(ls -1 "$MERGED_DIR"/*.sql 2>/dev/null | wc -l)"

        # Wait for PostgreSQL to be ready
        echo "Waiting for PostgreSQL..."
        for i in $(seq 1 30); do
          if podman exec helicone-db pg_isready -U postgres; then
            break
          fi
          sleep 2
        done

        # Run Flyway migrations on merged folder
        # The migrations_without_supabase files provide auth stubs (auth schema, auth.uid() function)
        # that the main supabase/migrations require
        echo "Running Flyway migrations..."
        podman run --rm \
          --network=${networkName} \
          -v "$MERGED_DIR:/flyway/sql:ro" \
          flyway/flyway:latest \
          -url="jdbc:postgresql://${dbHost}:5432/postgres" \
          -user=postgres \
          -password="${cfg.secrets.postgresPassword}" \
          -baselineOnMigrate=true \
          -locations="filesystem:/flyway/sql" \
          -sqlMigrationPrefix= \
          -sqlMigrationSeparator=_ \
          -sqlMigrationSuffixes=.sql \
          migrate || echo "Migrations may have already been applied"

        echo "PostgreSQL migrations complete."
      '';
    };

    # ClickHouse migrations
    systemd.services.helicone-clickhouse-migrate = {
      description = "Run Helicone ClickHouse migrations";
      wantedBy = [ "multi-user.target" ];
      after = [ "podman-helicone-clickhouse.service" "helicone-network.service" ];
      before = [ "podman-helicone-jawn.service" ];
      requires = [ "podman-helicone-clickhouse.service" ];

      path = [ pkgs.podman ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "5min";
      };

      script = ''
        set -e
        echo "Waiting for ClickHouse..."
        for i in $(seq 1 30); do
          if podman exec helicone-clickhouse clickhouse-client --query "SELECT 1" 2>/dev/null; then
            break
          fi
          sleep 2
        done

        echo "Running ClickHouse migrations..."
        podman run --rm \
          --network=${networkName} \
          -e CLICKHOUSE_HOST=${clickhouseHost} \
          -e CLICKHOUSE_PORT=8123 \
          helicone/clickhouse-migrations:latest || echo "ClickHouse migrations may have already been applied"

        echo "ClickHouse migrations complete."
      '';
    };

    # MinIO bucket initialization
    systemd.services.helicone-minio-init = {
      description = "Create Helicone S3 buckets";
      wantedBy = [ "multi-user.target" ];
      after = [ "podman-helicone-minio.service" "helicone-network.service" ];
      before = [ "podman-helicone-jawn.service" ];
      requires = [ "podman-helicone-minio.service" ];

      path = [ pkgs.podman ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "2min";
      };

      script = ''
        set -e
        echo "Waiting for MinIO..."
        for i in $(seq 1 30); do
          if podman exec helicone-minio curl -sf http://localhost:9000/minio/health/live; then
            break
          fi
          sleep 2
        done

        echo "Configuring MinIO client and creating buckets..."
        podman run --rm \
          --network=${networkName} \
          --entrypoint=/bin/sh \
          minio/mc:latest \
          -c "
            mc alias set myminio http://${minioHost}:9000 ${cfg.secrets.s3AccessKey} ${cfg.secrets.s3SecretKey} && \
            mc mb --ignore-existing myminio/request-response-storage && \
            mc anonymous set download myminio/request-response-storage && \
            echo 'Buckets created successfully'
          "

        echo "MinIO initialization complete."
      '';
    };

    virtualisation.oci-containers = {
      backend = "podman";

      containers = {
        # PostgreSQL Database
        helicone-db = {
          image = cfg.images.postgres;
          environment = {
            POSTGRES_USER = "postgres";
            POSTGRES_PASSWORD = cfg.secrets.postgresPassword;
            POSTGRES_DB = "postgres";
          };
          volumes = [
            "${cfg.dataDir}/postgres:/var/lib/postgresql/data"
          ];
          extraOptions = [
            "--network=${networkName}"
            "--health-cmd=pg_isready -U postgres"
            "--health-interval=10s"
          ];
        };

        # ClickHouse Analytics Database
        helicone-clickhouse = {
          image = cfg.images.clickhouse;
          environment = {
            CLICKHOUSE_USER = "default";
            CLICKHOUSE_PASSWORD = "";
          };
          volumes = [
            "${cfg.dataDir}/clickhouse:/var/lib/clickhouse"
          ];
          extraOptions = [
            "--network=${networkName}"
            "--health-cmd=clickhouse-client --query 'SELECT 1'"
            "--health-interval=10s"
          ];
        };

        # MinIO Object Storage - exposed for browser access to request/response bodies
        helicone-minio = {
          image = cfg.images.minio;
          cmd = [ "server" "/data" "--console-address" ":9001" ];
          ports = [
            "${toString cfg.ports.minio}:9000"
            "${toString cfg.ports.minioConsole}:9001"
          ];
          environment = {
            MINIO_ROOT_USER = cfg.secrets.s3AccessKey;
            MINIO_ROOT_PASSWORD = cfg.secrets.s3SecretKey;
          };
          volumes = [
            "${cfg.dataDir}/minio:/data"
          ];
          extraOptions = [
            "--network=${networkName}"
            "--health-cmd=curl -f http://localhost:9000/minio/health/live"
            "--health-interval=10s"
          ];
        };

        # Redis Cache
        helicone-redis = {
          image = cfg.images.redis;
          volumes = [
            "${cfg.dataDir}/redis:/data"
          ];
          extraOptions = [
            "--network=${networkName}"
            "--health-cmd=redis-cli ping"
            "--health-interval=10s"
          ];
        };

        # Jawn Backend API (waits for migrations via systemd)
        helicone-jawn = {
          image = cfg.images.jawn;
          dependsOn = [ "helicone-db" "helicone-clickhouse" "helicone-minio" "helicone-redis" ];
          # Note: helicone-migrate and helicone-clickhouse-migrate systemd services
          # are configured to run before this container starts
          ports = [ "${toString cfg.ports.jawn}:8585" ];
          environment = {
            # Database - multiple formats for compatibility
            DATABASE_URL = "postgresql://postgres:${cfg.secrets.postgresPassword}@${dbHost}:5432/postgres";
            POSTGRES_URL = "postgresql://postgres:${cfg.secrets.postgresPassword}@${dbHost}:5432/postgres";
            # Standard libpq environment variables
            PGHOST = dbHost;
            PGPORT = "5432";
            PGUSER = "postgres";
            PGPASSWORD = cfg.secrets.postgresPassword;
            PGDATABASE = "postgres";
            # Legacy env vars
            POSTGRES_HOST = dbHost;
            POSTGRES_PORT = "5432";
            POSTGRES_USER = "postgres";
            POSTGRES_PASSWORD = cfg.secrets.postgresPassword;
            POSTGRES_DB = "postgres";

            # ClickHouse - newer client requires full URL format
            CLICKHOUSE_URL = "http://${clickhouseHost}:8123";
            CLICKHOUSE_HOST = "http://${clickhouseHost}:8123";
            CLICKHOUSE_USER = "default";
            CLICKHOUSE_PASSWORD = "";

            # S3/MinIO - internal endpoint for Jawn
            S3_ENDPOINT = "http://${minioHost}:9000";
            S3_ACCESS_KEY = cfg.secrets.s3AccessKey;
            S3_SECRET_KEY = cfg.secrets.s3SecretKey;
            S3_BUCKET_NAME = "request-response-storage";
            S3_REGION = "us-east-1";
            # Public endpoint for browser access
            S3_PUBLIC_ENDPOINT = "http://${cfg.hostName}:${toString cfg.ports.minio}";

            # Redis
            REDIS_URL = "redis://${redisHost}:6379";

            # Auth
            BETTER_AUTH_SECRET = cfg.secrets.betterAuthSecret;

            # Self-hosted
            JAWN_PORT = "8585";
            IS_ON_PREM = "true";
            APP_URL = "http://${cfg.hostName}:${toString cfg.ports.web}";
          };
          extraOptions = [
            "--network=${networkName}"
          ];
        };

        # Web Frontend
        helicone-web = {
          image = cfg.images.web;
          dependsOn = [ "helicone-jawn" ];
          ports = [ "${toString cfg.ports.web}:3000" ];
          environment = {
            # Self-hosted URLs - these need to work at runtime
            NEXT_PUBLIC_BETTER_AUTH = "true";
            NEXT_PUBLIC_IS_ON_PREM = "true";
            BETTER_AUTH_URL = "http://${cfg.hostName}:${toString cfg.ports.web}";
            BETTER_AUTH_SECRET = cfg.secrets.betterAuthSecret;
            SITE_URL = "http://${cfg.hostName}:${toString cfg.ports.web}";

            # Backend connection (internal network)
            NEXT_PUBLIC_HELICONE_JAWN_SERVICE = "http://${cfg.hostName}:${toString cfg.ports.jawn}";
            JAWN_SERVICE_URL = "http://${jawnHost}:8585";

            # Database (for auth)
            DATABASE_URL = "postgresql://postgres:${cfg.secrets.postgresPassword}@${dbHost}:5432/postgres";
          };
          extraOptions = [
            "--network=${networkName}"
          ];
        };
      };
    };

    # Firewall
    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [
      cfg.ports.web
      cfg.ports.jawn
      cfg.ports.minio
      cfg.ports.minioConsole
    ];
  };
}

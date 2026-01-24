# Sandboxed OpenCode Agent - Implementation Plan

## Overview

Deploy a heavily sandboxed AI coding agent (`opencode`) with:
- **Filesystem isolation**: RW access only to `/mnt/agent1`, no access to other paths
- **Binary restriction**: Only shell + opencode + minimal dependencies
- **Network isolation**: All internet traffic routed through proxy
- **K3s deployment**: For flexibility, redundancy, and orchestration

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Host System (NixOS)                         │
├─────────────────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                    K3s Cluster (gpu-node-1)                    │ │
│  │  ┌──────────────────────────────────────────────────────────┐  │ │
│  │  │              opencode-agent Namespace                     │  │ │
│  │  │  ┌─────────────────┐  ┌─────────────────┐                │  │ │
│  │  │  │   Pod: agent-1  │  │   Pod: agent-2  │  (replicas)    │  │ │
│  │  │  │  ┌───────────┐  │  │  ┌───────────┐  │                │  │ │
│  │  │  │  │ Container │  │  │  │ Container │  │                │  │ │
│  │  │  │  │ opencode  │  │  │  │ opencode  │  │                │  │ │
│  │  │  │  │ + shell   │  │  │  │ + shell   │  │                │  │ │
│  │  │  │  └───────────┘  │  │  └───────────┘  │                │  │ │
│  │  │  │       ↓         │  │       ↓         │                │  │ │
│  │  │  │  /workspace     │  │  /workspace     │ ← hostPath     │  │ │
│  │  │  │  (RW mount)     │  │  (RW mount)     │   /mnt/agent1  │  │ │
│  │  │  └─────────────────┘  └─────────────────┘                │  │ │
│  │  │           │                    │                          │  │ │
│  │  │           └────────┬───────────┘                          │  │ │
│  │  │                    ↓                                      │  │ │
│  │  │  ┌──────────────────────────────────────────────────────┐│  │ │
│  │  │  │         NetworkPolicy: Egress via Proxy Only         ││  │ │
│  │  │  │         (squid/tinyproxy on 10.100.1.x:3128)         ││  │ │
│  │  │  └──────────────────────────────────────────────────────┘│  │ │
│  │  └──────────────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 1: NixOS Systemd Service (Non-K3s Option)

For standalone deployment without K3s, use heavy systemd sandboxing.

### 1.1 Module: `modules/opencode-sandbox/default.nix`

```nix
{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.services.opencode-sandbox;

  # Minimal shell environment
  sandboxedShell = pkgs.writeShellScriptBin "sandbox-shell" ''
    exec ${pkgs.dash}/bin/dash "$@"
  '';

  # Opencode with pinned dependencies
  opencode-pkg = inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.opencode.overrideAttrs (old: rec {
    version = "1.1.12";
    src = pkgs.fetchurl {
      url = "https://github.com/anomalyco/opencode/releases/download/v${version}/opencode-linux-x64.tar.gz";
      hash = "sha256-eiFuBbT1Grz1UBrGfg22z2AdCvE/6441vLVDD6L9DgE=";
    };
  });

  # Minimal FHS with only required binaries
  sandboxedOpencode = pkgs.buildFHSEnv {
    name = "opencode-sandboxed";

    targetPkgs = pkgs: [
      # Minimal shell
      pkgs.dash
      pkgs.coreutils-full

      # Required for opencode
      pkgs.cacert
      pkgs.git
      pkgs.curl

      # The agent itself
      opencode-pkg
    ];

    # NO additional binaries
    extraBwrapArgs = [
      "--unshare-all"
      "--share-net"  # Need network for proxy
      "--die-with-parent"
    ];

    runScript = "${opencode-pkg}/bin/opencode";
  };

in
{
  options.services.opencode-sandbox = {
    enable = lib.mkEnableOption "Sandboxed OpenCode AI agent";

    workDir = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/agent1";
      description = "Working directory (only RW path)";
    };

    proxy = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:3128";
      description = "HTTP/HTTPS proxy for internet access";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "opencode-agent";
      description = "Dedicated user for the sandbox";
    };

    apiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to file containing API key (e.g., Anthropic)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create dedicated user with no privileges
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      home = cfg.workDir;
      shell = pkgs.shadow;  # No login shell
      description = "Sandboxed OpenCode agent";
    };
    users.groups.${cfg.user} = {};

    # Create working directory
    systemd.tmpfiles.rules = [
      "d ${cfg.workDir} 0750 ${cfg.user} ${cfg.user} -"
    ];

    # Heavy sandboxing via systemd
    systemd.services.opencode-sandbox = {
      description = "Sandboxed OpenCode AI Agent";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      environment = {
        HOME = cfg.workDir;
        OPENCODE_CONFIG_HOME = "${cfg.workDir}/.config/opencode";

        # Force all traffic through proxy
        HTTP_PROXY = cfg.proxy;
        HTTPS_PROXY = cfg.proxy;
        http_proxy = cfg.proxy;
        https_proxy = cfg.proxy;
        NO_PROXY = "localhost,127.0.0.1";

        # SSL certs
        SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
        NIX_SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
      };

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.user;

        ExecStart = "${sandboxedOpencode}/bin/opencode-sandboxed";
        Restart = "on-failure";
        RestartSec = "10s";

        WorkingDirectory = cfg.workDir;

        # ========================================
        # HEAVY SANDBOXING - Systemd Hardening
        # ========================================

        # Namespace isolation
        PrivateUsers = true;
        PrivateTmp = true;
        PrivateDevices = true;
        PrivateIPC = true;
        PrivateMounts = true;

        # Network: allow only for proxy connection
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];

        # Filesystem: strict read-only except workdir
        ProtectSystem = "strict";
        ProtectHome = "yes";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectProc = "invisible";
        ProtectHostname = true;
        ProtectClock = true;

        # Only allow RW to work directory
        ReadWritePaths = [ cfg.workDir ];
        ReadOnlyPaths = [ "/etc/ssl/certs" ];
        InaccessiblePaths = [
          "/home"
          "/root"
          "/var"
          "/mnt"
          "-${cfg.workDir}"  # Except our workdir
        ];
        TemporaryFileSystem = "/mnt:ro";  # Mount empty tmpfs, then bind our dir
        BindPaths = [ "${cfg.workDir}:/mnt/agent1" ];

        # Capabilities: none
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";
        NoNewPrivileges = true;

        # Syscall filtering
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
          "~@mount"
          "~@swap"
          "~@reboot"
          "~@module"
          "~@raw-io"
        ];
        SystemCallArchitectures = "native";

        # Memory protections
        MemoryDenyWriteExecute = true;
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RemoveIPC = true;

        # Limit resources
        LimitNOFILE = 1024;
        LimitNPROC = 50;
        MemoryMax = "4G";
        CPUQuota = "200%";  # 2 cores max
      };
    };

    # Proxy service (if not already running)
    services.tinyproxy = lib.mkIf (cfg.proxy == "http://127.0.0.1:3128") {
      enable = true;
      settings = {
        Port = 3128;
        Listen = "127.0.0.1";
        MaxClients = 10;

        # Log for auditing
        LogFile = "/var/log/tinyproxy/tinyproxy.log";
        LogLevel = "Info";

        # Allow only localhost
        Allow = [ "127.0.0.1/8" ];
      };
    };
  };
}
```

### 1.2 Usage in Host Configuration

```nix
# hosts/gpu-node-1/configuration.nix
{
  imports = [
    ../../modules/opencode-sandbox
  ];

  services.opencode-sandbox = {
    enable = true;
    workDir = "/mnt/agent1";
    proxy = "http://127.0.0.1:3128";
    # apiKeyFile = /run/secrets/anthropic-api-key;
  };
}
```

---

## Part 2: K3s Deployment (Kubernetes)

For flexibility and redundancy, deploy as Kubernetes workload.

### 2.1 Container Image: `flakes/opencode-sandbox/Dockerfile`

```dockerfile
# Multi-stage build for minimal image
FROM nixos/nix:latest AS builder

WORKDIR /build
COPY flake.nix flake.lock ./

# Build the sandboxed environment
RUN nix build .#opencode-sandboxed --extra-experimental-features "nix-command flakes"

# Minimal runtime image
FROM gcr.io/distroless/base-debian12:nonroot

# Copy only the Nix closure
COPY --from=builder /nix/store /nix/store
COPY --from=builder /build/result/bin/opencode-sandboxed /usr/local/bin/opencode

# SSL certs
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Non-root user
USER 65532:65532
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/opencode"]
```

### 2.2 Kubernetes Manifests

#### Namespace and RBAC
```yaml
# k8s/opencode-agent/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: opencode-agent
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
---
# ServiceAccount with no permissions
apiVersion: v1
kind: ServiceAccount
metadata:
  name: opencode-agent
  namespace: opencode-agent
automountServiceAccountToken: false
```

#### Network Policy (Egress via Proxy Only)
```yaml
# k8s/opencode-agent/networkpolicy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: opencode-egress-proxy-only
  namespace: opencode-agent
spec:
  podSelector:
    matchLabels:
      app: opencode-agent
  policyTypes:
    - Ingress
    - Egress
  ingress: []  # No ingress allowed
  egress:
    # DNS resolution (required for proxy hostname)
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
    # Proxy only (adjust IP for your proxy)
    - to:
        - ipBlock:
            cidr: 10.100.1.0/24  # K3s VLAN
      ports:
        - protocol: TCP
          port: 3128  # Squid/Tinyproxy
```

#### PersistentVolume for /mnt/agent1
```yaml
# k8s/opencode-agent/storage.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: agent1-workspace
spec:
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteMany
  hostPath:
    path: /mnt/agent1
    type: DirectoryOrCreate
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-path
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: agent1-workspace
  namespace: opencode-agent
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 100Gi
  storageClassName: local-path
  volumeName: agent1-workspace
```

#### Deployment with Security Context
```yaml
# k8s/opencode-agent/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: opencode-agent
  namespace: opencode-agent
spec:
  replicas: 2  # Redundancy
  selector:
    matchLabels:
      app: opencode-agent
  template:
    metadata:
      labels:
        app: opencode-agent
    spec:
      serviceAccountName: opencode-agent
      automountServiceAccountToken: false

      # Pod-level security
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        runAsGroup: 65532
        fsGroup: 65532
        seccompProfile:
          type: RuntimeDefault

      containers:
        - name: opencode
          image: ghcr.io/yourusername/opencode-sandboxed:v1.1.12
          imagePullPolicy: IfNotPresent

          # Container security
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
            seccompProfile:
              type: RuntimeDefault

          env:
            - name: HOME
              value: /workspace
            - name: OPENCODE_CONFIG_HOME
              value: /workspace/.config/opencode
            # Proxy configuration
            - name: HTTP_PROXY
              value: "http://squid-proxy.kube-system.svc:3128"
            - name: HTTPS_PROXY
              value: "http://squid-proxy.kube-system.svc:3128"
            - name: NO_PROXY
              value: "localhost,127.0.0.1,.cluster.local"
            # API key from secret
            - name: ANTHROPIC_API_KEY
              valueFrom:
                secretKeyRef:
                  name: opencode-secrets
                  key: anthropic-api-key

          volumeMounts:
            - name: workspace
              mountPath: /workspace
            - name: tmp
              mountPath: /tmp
            - name: ssl-certs
              mountPath: /etc/ssl/certs
              readOnly: true

          resources:
            requests:
              memory: "512Mi"
              cpu: "500m"
            limits:
              memory: "4Gi"
              cpu: "2000m"

      volumes:
        - name: workspace
          persistentVolumeClaim:
            claimName: agent1-workspace
        - name: tmp
          emptyDir:
            sizeLimit: 1Gi
        - name: ssl-certs
          hostPath:
            path: /etc/ssl/certs
            type: Directory

      # Scheduling
      nodeSelector:
        kubernetes.io/os: linux

      tolerations: []
```

#### Secret for API Keys
```yaml
# k8s/opencode-agent/secrets.yaml (use sealed-secrets or external-secrets in production)
apiVersion: v1
kind: Secret
metadata:
  name: opencode-secrets
  namespace: opencode-agent
type: Opaque
stringData:
  anthropic-api-key: "sk-ant-xxxxx"  # Replace with actual key
```

### 2.3 Proxy Deployment (Squid in K3s)

```yaml
# k8s/kube-system/squid-proxy.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: squid-proxy
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: squid-proxy
  template:
    metadata:
      labels:
        app: squid-proxy
    spec:
      containers:
        - name: squid
          image: ubuntu/squid:latest
          ports:
            - containerPort: 3128
          volumeMounts:
            - name: squid-config
              mountPath: /etc/squid/squid.conf
              subPath: squid.conf
          resources:
            limits:
              memory: "512Mi"
              cpu: "500m"
      volumes:
        - name: squid-config
          configMap:
            name: squid-config
---
apiVersion: v1
kind: Service
metadata:
  name: squid-proxy
  namespace: kube-system
spec:
  selector:
    app: squid-proxy
  ports:
    - port: 3128
      targetPort: 3128
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: squid-config
  namespace: kube-system
data:
  squid.conf: |
    # Minimal secure squid config
    acl localnet src 10.0.0.0/8
    acl localnet src 172.16.0.0/12
    acl SSL_ports port 443
    acl Safe_ports port 80 443

    http_access deny !Safe_ports
    http_access deny CONNECT !SSL_ports
    http_access allow localnet
    http_access deny all

    http_port 3128

    # Logging
    access_log daemon:/var/log/squid/access.log squid

    # Cache (minimal)
    cache_mem 64 MB
    maximum_object_size 10 MB
```

---

## Part 3: NixOS K3s Integration

### 3.1 Deploy K8s Manifests via NixOS

```nix
# modules/opencode-sandbox/k3s.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.services.opencode-sandbox-k3s;

  # Kubernetes manifests as a package
  k8s-manifests = pkgs.writeTextDir "manifests/opencode-agent.yaml" ''
    # Combined manifest (namespace, networkpolicy, deployment, etc.)
    ${builtins.readFile ./k8s/namespace.yaml}
    ---
    ${builtins.readFile ./k8s/networkpolicy.yaml}
    ---
    ${builtins.readFile ./k8s/storage.yaml}
    ---
    ${builtins.readFile ./k8s/deployment.yaml}
  '';

in
{
  options.services.opencode-sandbox-k3s = {
    enable = lib.mkEnableOption "OpenCode agent on K3s";

    replicas = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Number of agent replicas";
    };

    workDir = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/agent1";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure K3s is enabled
    assertions = [
      {
        assertion = config.services.k3s.enable;
        message = "K3s must be enabled for opencode-sandbox-k3s";
      }
    ];

    # Create host directory
    systemd.tmpfiles.rules = [
      "d ${cfg.workDir} 0755 65532 65532 -"
    ];

    # Deploy manifests automatically
    environment.etc."rancher/k3s/server/manifests/opencode-agent.yaml".source =
      "${k8s-manifests}/manifests/opencode-agent.yaml";
  };
}
```

---

## Part 4: Implementation Steps

### Phase 1: Proxy Infrastructure
1. Deploy tinyproxy or squid on K3s cluster
2. Configure logging for audit trail
3. Test proxy connectivity from pods

### Phase 2: Container Image
1. Create `flakes/opencode-sandbox/flake.nix` with minimal closure
2. Build container image with Nix
3. Push to container registry (ghcr.io or local)

### Phase 3: K8s Deployment
1. Apply namespace with pod security standards
2. Deploy NetworkPolicy for proxy-only egress
3. Create PV/PVC for `/mnt/agent1`
4. Deploy opencode-agent with secrets

### Phase 4: Testing
1. Verify filesystem isolation (can't access /home, /root, etc.)
2. Verify network isolation (can't reach internet directly)
3. Verify proxy logging captures all requests
4. Test redundancy (kill one pod, verify failover)

### Phase 5: Monitoring
1. Add Prometheus metrics endpoint
2. Configure alerts for pod restarts
3. Set up log aggregation (Loki or Fluentd)

---

## Security Summary

| Layer | Mechanism | Protection |
|-------|-----------|------------|
| Filesystem | PV mount only /mnt/agent1 | No access to host FS |
| Filesystem | readOnlyRootFilesystem | Immutable container |
| Network | NetworkPolicy | Egress via proxy only |
| Network | Proxy logging | Full request audit |
| Process | seccompProfile: RuntimeDefault | Syscall filtering |
| Process | capabilities: drop ALL | No privileged ops |
| User | runAsNonRoot: 65532 | Non-root execution |
| K8s | Pod Security Standards | Restricted enforcement |
| Resources | CPU/Memory limits | DoS protection |

---

## Files to Create

```
modules/opencode-sandbox/
├── default.nix          # Systemd service option
├── k3s.nix              # K3s integration module
└── k8s/
    ├── namespace.yaml
    ├── networkpolicy.yaml
    ├── storage.yaml
    ├── deployment.yaml
    └── secrets.yaml

flakes/opencode-sandbox/
├── flake.nix            # Build sandboxed package
└── Dockerfile           # Container image
```

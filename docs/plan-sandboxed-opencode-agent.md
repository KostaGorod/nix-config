# Sandboxed OpenCode Agent - Implementation Plan

## Overview

Deploy a heavily sandboxed AI coding agent (`opencode`) with:
- **Filesystem isolation**: RW access only to `/mnt/agent1`, no access to other paths
- **Binary restriction**: Only shell + opencode + minimal dependencies
- **Network isolation**: All internet traffic routed through proxy
- **Dynamic runtime**: Spawn/destroy agents without nixos-rebuild
- **K3s deployment**: For flexibility, redundancy, and orchestration
- **OS-agnostic workloads**: Agents run in OCI containers, portable across platforms

---

## OS-Agnostic Architecture

For portability, separate **infrastructure** (NixOS-managed) from **workloads** (containerized).

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        DECLARATIVE (NixOS)                                  │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │ • K3s cluster setup          • Networking (proxy, firewall, VLAN)     │  │
│  │ • Storage (/mnt/agents PV)   • Secrets (sops-nix / agenix)            │  │
│  │ • Monitoring (Prometheus)    • DNS / Tailscale                        │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                    │                                        │
│                                    ▼                                        │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                     K3s / Kubernetes API                              │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                    │                                        │
└────────────────────────────────────┼────────────────────────────────────────┘
                                     │
┌────────────────────────────────────┼────────────────────────────────────────┐
│                        PORTABLE (OCI / K8s)                                 │
│                                    ▼                                        │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                    Agent OCI Image (multi-arch)                       │  │
│  │  • opencode binary           • sandbox-runtime                        │  │
│  │  • Minimal shell (dash)      • Agent card processor                   │  │
│  │  • git, curl, certs          • Entrypoint script                      │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                    │                                        │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                    Kubernetes Manifests (GitOps)                      │  │
│  │  • Namespace + RBAC          • NetworkPolicy (proxy-only egress)      │  │
│  │  • Deployment/StatefulSet    • PVC for workspace                      │  │
│  │  • ConfigMap (agent cards)   • Secrets (API keys)                     │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  Runs on: NixOS K3s │ AWS EKS │ GCP GKE │ Azure AKS │ Any K8s              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### What Lives Where

| Component | NixOS (Declarative) | K8s/OCI (Portable) | Why |
|-----------|--------------------|--------------------|-----|
| K3s cluster | ✅ | - | Host-specific |
| Proxy (squid) | ✅ or K8s | ✅ | Can be either |
| Storage provisioner | ✅ | - | Host storage |
| Agent image | - | ✅ | Portable |
| Agent card schema | - | ✅ | App config |
| NetworkPolicy | - | ✅ | K8s native |
| Secrets backend | ✅ (sops/agenix) | ✅ (external-secrets) | Both work |
| Monitoring | ✅ or K8s | ✅ | Can be either |

### Benefits

1. **Portability**: Same agent image runs on any K8s cluster
2. **GitOps**: K8s manifests in Git, deploy with ArgoCD/Flux
3. **Scaling**: HPA/KEDA for auto-scaling agents
4. **Multi-cloud**: Failover between clusters
5. **NixOS advantages**: Declarative infra, reproducible hosts

---

## Built-in Sandboxing Status

| Tool | Native Sandbox | Implementation | Notes |
|------|----------------|----------------|-------|
| **Claude Code** | ✅ Yes | Seatbelt (macOS), bubblewrap (Linux) | Full FS + network isolation, [open source runtime](https://github.com/anthropic-experimental/sandbox-runtime) |
| **OpenCode** | ❌ No | N/A | [Requested feature](https://github.com/anomalyco/opencode/issues/2242), community uses Docker |

**Key insight**: Claude Code already uses bubblewrap on Linux. For OpenCode, external sandboxing is required.

## NixOS Sandboxing Comparison

| Option | Rebuild? | Dynamic? | FS Isolation | Net Isolation | NixOS Native | Notes |
|--------|----------|----------|--------------|---------------|--------------|-------|
| **buildFHSEnv** | Yes | No | Partial (chroot-like) | None | ✅ | Binary compat, not security sandbox |
| **bubblewrap** | No | Yes | Full (namespaces) | Via proxy | ✅ (in pkgs) | What Claude Code uses; [actively maintained](https://github.com/containers/bubblewrap) |
| **systemd-nspawn** | No | Yes | Full (container) | netns | ✅ | Heavier, full container |
| **nixos-container** | Yes | No | Full (nspawn) | netns | ✅ | Declarative but static |
| **Podman rootless** | No | Yes | Full (OCI) | netns | Partial | Needs OCI image |
| **sandbox-runtime** | No | Yes | Full | Full | Via npm | Claude's open source package |

### buildFHSEnv vs bubblewrap

| Aspect | buildFHSEnv | bubblewrap |
|--------|-------------|------------|
| **Purpose** | Binary compatibility (FHS layout) | Security isolation |
| **Namespaces** | None (just bind mounts) | User, mount, PID, net, IPC |
| **FS isolation** | Sees host paths | Can hide entire FS |
| **Network** | Full host access | Can isolate or restrict |
| **Runtime spawn** | No (needs rebuild) | Yes (just exec) |
| **Use case** | Run proprietary binaries | Sandbox untrusted code |

**buildFHSEnv is NOT a security sandbox** - it's for running binaries that expect `/usr/lib`, `/lib64`, etc.

### Bubblewrap Maintenance Status

Bubblewrap is **actively maintained** under [containers/bubblewrap](https://github.com/containers/bubblewrap):
- CVE-2024-42472 patched (symlink security fix)
- New features: `--bind-fd`, `--overlay` support
- Used by: Flatpak, GNOME, Claude Code, Firefox
- Latest: v0.10.0 (2024)

## Recommended Approach

**For OpenCode**: Use bubblewrap + systemd templates (since OpenCode lacks native sandboxing)
**For Claude Code**: Leverage its native sandbox, configure via `settings.json`

| Agent | Recommended Sandbox |
|-------|-------------------|
| Claude Code | Native (`/sandbox` command) + proxy for network audit |
| OpenCode | bubblewrap wrapper OR Claude's sandbox-runtime + systemd template |
| Both | K3s pods with NetworkPolicy (for multi-agent orchestration) |

### Option: Use Claude's sandbox-runtime for OpenCode (Recommended)

Anthropic open-sourced their sandbox runtime under **Apache 2.0** - commercial use allowed.

| Permission | Apache 2.0 |
|------------|------------|
| Commercial use | ✅ Allowed |
| Modification | ✅ Allowed |
| Distribution | ✅ Allowed |
| Patent grant | ✅ Included |

**Repository**: https://github.com/anthropic-experimental/sandbox-runtime

```bash
# Install once
npm install -g @anthropic-ai/sandbox-runtime

# Sandbox any command (including opencode)
npx @anthropic-ai/sandbox-runtime opencode
```

### NixOS Module for sandbox-runtime

```nix
# modules/sandbox-runtime/default.nix
{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.programs.sandbox-runtime;

  # Build sandbox-runtime from npm
  sandbox-runtime = pkgs.buildNpmPackage rec {
    pname = "sandbox-runtime";
    version = "0.1.0";  # Check latest version

    src = pkgs.fetchFromGitHub {
      owner = "anthropic-experimental";
      repo = "sandbox-runtime";
      rev = "main";  # Pin to specific commit in production
      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";  # Update
    };

    npmDepsHash = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";  # Update

    # Needs bubblewrap and socat at runtime
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postInstall = ''
      wrapProgram $out/bin/sandbox-runtime \
        --prefix PATH : ${lib.makeBinPath [ pkgs.bubblewrap pkgs.socat ]}
    '';
  };

  opencode-pkg = inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.opencode;

  # Wrapper that spawns opencode inside sandbox-runtime
  opencode-sandboxed = pkgs.writeShellScriptBin "opencode-sandboxed" ''
    set -euo pipefail

    # Agent ID card support (optional)
    if [[ -n "''${AGENT_CARD:-}" && -f "$AGENT_CARD" ]]; then
      WORKSPACE=$(${pkgs.jq}/bin/jq -r '.workspace' "$AGENT_CARD")
      PROXY=$(${pkgs.jq}/bin/jq -r '.proxy // ""' "$AGENT_CARD")
      API_KEY_FILE=$(${pkgs.jq}/bin/jq -r '.api_key_file // ""' "$AGENT_CARD")

      [[ -n "$PROXY" ]] && export HTTP_PROXY="$PROXY" HTTPS_PROXY="$PROXY"
      [[ -n "$API_KEY_FILE" && -f "$API_KEY_FILE" ]] && export ANTHROPIC_API_KEY=$(cat "$API_KEY_FILE")

      cd "$WORKSPACE"
    fi

    exec ${sandbox-runtime}/bin/sandbox-runtime \
      ${opencode-pkg}/bin/opencode "$@"
  '';

  # Agent spawner using sandbox-runtime
  agent-spawn = pkgs.writeShellScriptBin "agent-spawn" ''
    set -euo pipefail

    CARD_FILE="''${1:-}"
    if [[ -z "$CARD_FILE" || ! -f "$CARD_FILE" ]]; then
      echo "Usage: agent-spawn <agent-card.json> [args...]"
      exit 1
    fi

    AGENT_ID=$(${pkgs.jq}/bin/jq -r '.agent_id' "$CARD_FILE")
    WORKSPACE=$(${pkgs.jq}/bin/jq -r '.workspace' "$CARD_FILE")
    PROXY=$(${pkgs.jq}/bin/jq -r '.proxy // ""' "$CARD_FILE")
    API_KEY_FILE=$(${pkgs.jq}/bin/jq -r '.api_key_file // ""' "$CARD_FILE")
    TTL=$(${pkgs.jq}/bin/jq -r '.ttl_seconds // 0' "$CARD_FILE")

    mkdir -p "$WORKSPACE"

    echo "[agent-spawn] Starting: $AGENT_ID"
    echo "[agent-spawn] Workspace: $WORKSPACE"

    # Build environment
    ENV_ARGS=()
    [[ -n "$PROXY" ]] && ENV_ARGS+=(--setenv HTTP_PROXY "$PROXY" --setenv HTTPS_PROXY "$PROXY")
    [[ -n "$API_KEY_FILE" && -f "$API_KEY_FILE" ]] && ENV_ARGS+=(--setenv ANTHROPIC_API_KEY "$(cat "$API_KEY_FILE")")

    # Optional TTL
    TIMEOUT_CMD=""
    [[ "$TTL" -gt 0 ]] && TIMEOUT_CMD="${pkgs.coreutils}/bin/timeout $TTL"

    cd "$WORKSPACE"
    exec $TIMEOUT_CMD ${sandbox-runtime}/bin/sandbox-runtime \
      ${opencode-pkg}/bin/opencode "''${@:2}"
  '';

in
{
  options.programs.sandbox-runtime = {
    enable = lib.mkEnableOption "Anthropic sandbox-runtime for agent isolation";

    agentsDir = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/agents";
      description = "Base directory for agent workspaces";
    };

    proxy = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Default HTTP proxy for network auditing";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      sandbox-runtime
      opencode-sandboxed
      agent-spawn
      pkgs.bubblewrap
      pkgs.socat
      pkgs.jq
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.agentsDir} 0755 root root -"
    ];

    # Systemd template for managed agents
    systemd.services."sandboxed-agent@" = {
      description = "Sandboxed Agent %i";
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${agent-spawn}/bin/agent-spawn /etc/agents/%i.json";
        Restart = "on-failure";
        RestartSec = "10s";

        # Defense in depth (systemd limits on top of sandbox)
        MemoryMax = "4G";
        CPUQuota = "200%";
        TasksMax = 100;

        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "agent-%i";
      };
    };
  };
}
```

### Usage

```bash
# Direct sandboxed opencode
opencode-sandboxed

# With agent card
cat > /etc/agents/dev.json << 'EOF'
{
  "agent_id": "dev",
  "workspace": "/mnt/agents/dev",
  "proxy": "http://127.0.0.1:3128",
  "api_key_file": "/run/secrets/anthropic-key"
}
EOF

# Spawn dynamically (no rebuild)
agent-spawn /etc/agents/dev.json

# Or via systemd
systemctl start sandboxed-agent@dev
journalctl -fu sandboxed-agent@dev
```

Benefits:
- **Apache 2.0** - commercial use allowed
- Same battle-tested sandbox as Claude Code
- FS + network isolation out of the box
- Domain allowlist via proxy
- Maintained by Anthropic
- NixOS-native with systemd templates

---

## Portable OCI Image (OS-Agnostic)

Build the agent as an OCI image using Nix - runs on any K8s cluster.

### OCI Image with Nix (nix2container)

```nix
# flakes/opencode-agent-image/flake.nix
{
  description = "Portable OpenCode Agent OCI Image";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix2container.url = "github:nlewo/nix2container";
    nix-ai-tools.url = "github:your-org/nix-ai-tools";  # Or your source
  };

  outputs = { self, nixpkgs, nix2container, nix-ai-tools, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          n2c = nix2container.packages.${system}.nix2container;

          # OpenCode binary
          opencode = nix-ai-tools.packages.${system}.opencode;

          # Entrypoint that processes agent card
          entrypoint = pkgs.writeShellScriptBin "entrypoint" ''
            set -euo pipefail

            # Agent card from ConfigMap mount or env
            CARD_FILE="''${AGENT_CARD_FILE:-/etc/agent/card.json}"

            if [[ -f "$CARD_FILE" ]]; then
              export AGENT_ID=$(${pkgs.jq}/bin/jq -r '.agent_id // "unknown"' "$CARD_FILE")

              # API key from file (K8s secret mount)
              API_KEY_FILE=$(${pkgs.jq}/bin/jq -r '.api_key_file // ""' "$CARD_FILE")
              if [[ -n "$API_KEY_FILE" && -f "$API_KEY_FILE" ]]; then
                export ANTHROPIC_API_KEY=$(cat "$API_KEY_FILE")
              fi
            fi

            echo "[agent] Starting: ''${AGENT_ID:-unnamed}"
            echo "[agent] Workspace: $PWD"

            exec ${opencode}/bin/opencode "$@"
          '';

          # Minimal agent image
          agentImage = n2c.buildImage {
            name = "opencode-agent";
            tag = "v${opencode.version}";

            # Multi-arch support
            maxLayers = 50;

            copyToRoot = pkgs.buildEnv {
              name = "agent-root";
              paths = [
                # Minimal shell
                pkgs.dash
                pkgs.coreutils

                # Required tools
                pkgs.git
                pkgs.curl
                pkgs.cacert
                pkgs.jq

                # The agent
                opencode
                entrypoint
              ];
              pathsToLink = [ "/bin" "/etc" "/lib" ];
            };

            config = {
              Entrypoint = [ "${entrypoint}/bin/entrypoint" ];
              WorkingDir = "/workspace";
              User = "65532:65532";  # nonroot

              Env = [
                "HOME=/workspace"
                "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
                "PATH=/bin"
              ];

              Labels = {
                "org.opencontainers.image.source" = "https://github.com/your-org/nix-config";
                "org.opencontainers.image.description" = "Sandboxed OpenCode Agent";
                "org.opencontainers.image.licenses" = "Apache-2.0";
              };
            };
          };

        in {
          default = agentImage;
          opencode-agent = agentImage;

          # Push helper
          push = pkgs.writeShellScriptBin "push-image" ''
            ${n2c}/bin/skopeo copy \
              nix:${agentImage} \
              docker://ghcr.io/your-org/opencode-agent:v${opencode.version}
          '';
        }
      );
    };
}
```

### Build & Push

```bash
# Build image (outputs to Nix store)
nix build .#opencode-agent

# Load into local Docker/Podman
nix run .#opencode-agent.copyToDockerDaemon

# Push to registry
nix run .#push
# Or manually:
skopeo copy nix:./result docker://ghcr.io/your-org/opencode-agent:latest
```

---

## Portable K8s Manifests (GitOps)

These manifests work on **any Kubernetes cluster** - not NixOS-specific.

### Directory Structure

```
k8s/opencode-agent/
├── kustomization.yaml      # Kustomize base
├── namespace.yaml
├── networkpolicy.yaml
├── rbac.yaml
├── configmap.yaml          # Agent cards
├── deployment.yaml
├── pvc.yaml
└── overlays/
    ├── dev/
    │   └── kustomization.yaml
    └── prod/
        └── kustomization.yaml
```

### Base Manifests

```yaml
# k8s/opencode-agent/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: opencode-agent

resources:
  - namespace.yaml
  - rbac.yaml
  - networkpolicy.yaml
  - configmap.yaml
  - pvc.yaml
  - deployment.yaml

images:
  - name: opencode-agent
    newName: ghcr.io/your-org/opencode-agent
    newTag: latest
```

```yaml
# k8s/opencode-agent/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: opencode-agent
  labels:
    # Pod Security Standards - restricted
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

```yaml
# k8s/opencode-agent/networkpolicy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: agent-egress-proxy-only
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: opencode-agent
  policyTypes:
    - Ingress
    - Egress
  ingress: []  # No inbound traffic
  egress:
    # DNS
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
    # Proxy only (configure for your cluster)
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              app: squid-proxy
      ports:
        - protocol: TCP
          port: 3128
```

```yaml
# k8s/opencode-agent/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: agent-cards
data:
  # Agent ID cards - one per agent type
  default.json: |
    {
      "agent_id": "default",
      "workspace": "/workspace",
      "proxy": "http://squid-proxy.kube-system:3128",
      "api_key_file": "/secrets/api-key",
      "resource_limits": {
        "memory_mb": 4096,
        "max_processes": 50
      },
      "allowed_hosts": [
        "api.anthropic.com",
        "api.openai.com"
      ]
    }
```

```yaml
# k8s/opencode-agent/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: opencode-agent
  labels:
    app.kubernetes.io/name: opencode-agent
spec:
  replicas: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: opencode-agent
  template:
    metadata:
      labels:
        app.kubernetes.io/name: opencode-agent
    spec:
      serviceAccountName: opencode-agent
      automountServiceAccountToken: false

      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        runAsGroup: 65532
        fsGroup: 65532
        seccompProfile:
          type: RuntimeDefault

      containers:
        - name: agent
          image: opencode-agent  # Replaced by Kustomize
          imagePullPolicy: IfNotPresent

          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]

          env:
            - name: AGENT_CARD_FILE
              value: /etc/agent/card.json
            - name: HTTP_PROXY
              value: http://squid-proxy.kube-system:3128
            - name: HTTPS_PROXY
              value: http://squid-proxy.kube-system:3128
            - name: NO_PROXY
              value: localhost,127.0.0.1,.cluster.local

          volumeMounts:
            - name: workspace
              mountPath: /workspace
            - name: agent-card
              mountPath: /etc/agent
              readOnly: true
            - name: api-secret
              mountPath: /secrets
              readOnly: true
            - name: tmp
              mountPath: /tmp

          resources:
            requests:
              memory: "512Mi"
              cpu: "250m"
            limits:
              memory: "4Gi"
              cpu: "2"

      volumes:
        - name: workspace
          persistentVolumeClaim:
            claimName: agent-workspace
        - name: agent-card
          configMap:
            name: agent-cards
            items:
              - key: default.json
                path: card.json
        - name: api-secret
          secret:
            secretName: agent-api-keys
        - name: tmp
          emptyDir:
            sizeLimit: 1Gi
```

### Deploy Anywhere (GitOps)

K8s manifests deploy independently - no NixOS module needed.

```bash
# Any K8s cluster (manual)
kubectl apply -k k8s/opencode-agent/

# With ArgoCD
argocd app create opencode-agent \
  --repo https://github.com/your-org/k8s-manifests \
  --path k8s/opencode-agent \
  --dest-server https://kubernetes.default.svc

# With Flux
flux create kustomization opencode-agent \
  --source=GitRepository/infra \
  --path="./k8s/opencode-agent"
```

**NixOS only manages infrastructure** (K3s, storage, proxy, secrets) - not workloads.

---

## Captain Agent: Orchestrating Sandboxed Agents via A2A

A "captain" agent orchestrates worker agents, spinning them up/down dynamically and communicating via the [A2A protocol](https://a2a-protocol.org/latest/).

### A2A Protocol Overview

[Agent2Agent (A2A)](https://github.com/a2aproject/A2A) is Google's open protocol (now Linux Foundation) for agent interoperability:

| Concept | Description |
|---------|-------------|
| **Agent Card** | JSON at `/.well-known/agent.json` describing capabilities |
| **Task** | Unit of work with lifecycle (pending → running → completed/failed) |
| **Message** | Communication between agents (text, files, structured data) |
| **Artifact** | Output produced by agent (files, data) |

**A2A vs MCP**:
- **MCP** (Anthropic): Agent ↔ Tools (give agent access to APIs, DBs)
- **A2A** (Google): Agent ↔ Agent (agents collaborate on tasks)

### Architecture: Captain + Workers

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            Captain Agent                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  • Receives high-level tasks from user/API                          │    │
│  │  • Decomposes into subtasks                                         │    │
│  │  • Spawns sandboxed worker agents (via K8s API or systemd)          │    │
│  │  • Communicates with workers via A2A protocol                       │    │
│  │  • Aggregates results, reports back                                 │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│         │                    │                    │                          │
│         │ A2A                │ A2A                │ A2A                      │
│         ▼                    ▼                    ▼                          │
│  ┌─────────────┐      ┌─────────────┐      ┌─────────────┐                  │
│  │  Worker 1   │      │  Worker 2   │      │  Worker N   │                  │
│  │  (sandbox)  │      │  (sandbox)  │      │  (sandbox)  │                  │
│  │             │      │             │      │             │                  │
│  │ opencode    │      │ opencode    │      │ claude-code │                  │
│  │ /workspace1 │      │ /workspace2 │      │ /workspaceN │                  │
│  └─────────────┘      └─────────────┘      └─────────────┘                  │
│         │                    │                    │                          │
│         └────────────────────┴────────────────────┘                          │
│                              │                                               │
│                    ┌─────────┴─────────┐                                    │
│                    │   Shared Proxy    │  ← All network via proxy           │
│                    │   (audit log)     │                                    │
│                    └───────────────────┘                                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Agent Card for Worker Agents

Each worker exposes an A2A-compliant agent card:

```json
// /.well-known/agent.json (served by worker)
{
  "name": "opencode-worker",
  "description": "Sandboxed OpenCode agent for code tasks",
  "url": "http://worker-1.agents.svc:8080",
  "version": "1.0.0",
  "capabilities": {
    "streaming": true,
    "pushNotifications": false
  },
  "skills": [
    {
      "id": "code-generation",
      "name": "Code Generation",
      "description": "Generate code from natural language",
      "inputModes": ["text"],
      "outputModes": ["text", "file"]
    },
    {
      "id": "code-review",
      "name": "Code Review",
      "description": "Review and suggest improvements",
      "inputModes": ["text", "file"],
      "outputModes": ["text"]
    }
  ],
  "authentication": {
    "schemes": ["bearer"]
  }
}
```

### Captain Agent Implementation

```nix
# flakes/captain-agent/flake.nix
{
  description = "Captain agent that orchestrates sandboxed workers via A2A";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      pkgs = import nixpkgs { system = "x86_64-linux"; };

      # Captain agent script
      captainAgent = pkgs.writeShellScriptBin "captain-agent" ''
        set -euo pipefail

        # Captain config
        CAPTAIN_PORT="''${CAPTAIN_PORT:-8000}"
        WORKERS_DIR="''${WORKERS_DIR:-/var/lib/captain/workers}"
        K8S_NAMESPACE="''${K8S_NAMESPACE:-opencode-agents}"

        mkdir -p "$WORKERS_DIR"

        # Spawn a new worker agent
        spawn_worker() {
          local TASK_ID="$1"
          local WORKSPACE="/mnt/agents/$TASK_ID"

          # Create agent card for this worker
          cat > "$WORKERS_DIR/$TASK_ID.json" << EOF
        {
          "agent_id": "$TASK_ID",
          "workspace": "$WORKSPACE",
          "proxy": "http://squid-proxy:3128",
          "a2a_port": 8080
        }
        EOF

          # Option 1: Spawn via systemd (NixOS host)
          if command -v systemctl &>/dev/null; then
            systemctl start "sandboxed-agent@$TASK_ID"
          fi

          # Option 2: Spawn via K8s (portable)
          if command -v kubectl &>/dev/null; then
            kubectl -n "$K8S_NAMESPACE" run "worker-$TASK_ID" \
              --image=ghcr.io/your-org/opencode-agent:latest \
              --env="AGENT_ID=$TASK_ID" \
              --env="A2A_ENABLED=true" \
              --restart=Never
          fi

          echo "http://worker-$TASK_ID.$K8S_NAMESPACE.svc:8080"
        }

        # Terminate a worker
        terminate_worker() {
          local TASK_ID="$1"

          # Systemd
          systemctl stop "sandboxed-agent@$TASK_ID" 2>/dev/null || true

          # K8s
          kubectl -n "$K8S_NAMESPACE" delete pod "worker-$TASK_ID" 2>/dev/null || true

          rm -f "$WORKERS_DIR/$TASK_ID.json"
        }

        # Send A2A task to worker
        send_task() {
          local WORKER_URL="$1"
          local TASK_PAYLOAD="$2"

          ${pkgs.curl}/bin/curl -s -X POST "$WORKER_URL/tasks/send" \
            -H "Content-Type: application/json" \
            -d "$TASK_PAYLOAD"
        }

        # Get task status
        get_task_status() {
          local WORKER_URL="$1"
          local TASK_ID="$2"

          ${pkgs.curl}/bin/curl -s "$WORKER_URL/tasks/$TASK_ID"
        }

        # Main captain loop (simplified)
        echo "[captain] Starting on port $CAPTAIN_PORT"

        # In real implementation: HTTP server handling A2A requests
        # For now, expose simple CLI
        case "''${1:-}" in
          spawn)
            spawn_worker "$2"
            ;;
          terminate)
            terminate_worker "$2"
            ;;
          send)
            send_task "$2" "$3"
            ;;
          status)
            get_task_status "$2" "$3"
            ;;
          *)
            echo "Usage: captain-agent <spawn|terminate|send|status> [args]"
            ;;
        esac
      '';

      # A2A sidecar for workers (adds A2A HTTP endpoint)
      a2aSidecar = pkgs.writeShellScriptBin "a2a-sidecar" ''
        # Lightweight HTTP server that wraps agent with A2A protocol
        # In production: use proper A2A SDK (Python/TypeScript)

        PORT="''${A2A_PORT:-8080}"
        AGENT_CMD="''${AGENT_CMD:-opencode}"

        # Serve agent card
        serve_agent_card() {
          cat << 'EOF'
        HTTP/1.1 200 OK
        Content-Type: application/json

        {"name":"opencode-worker","version":"1.0","skills":[{"id":"code"}]}
        EOF
        }

        echo "[a2a-sidecar] Listening on :$PORT"
        # In production: use socat or proper HTTP server
        while true; do
          echo "Waiting for A2A requests..."
          sleep 1
        done
      '';

    in {
      packages.x86_64-linux = {
        default = captainAgent;
        captain-agent = captainAgent;
        a2a-sidecar = a2aSidecar;
      };
    };
}
```

### A2A Communication Flow

```
┌──────────┐                    ┌──────────┐                    ┌──────────┐
│  User    │                    │ Captain  │                    │ Worker   │
└────┬─────┘                    └────┬─────┘                    └────┬─────┘
     │                               │                               │
     │  "Build a REST API"           │                               │
     │ ─────────────────────────────>│                               │
     │                               │                               │
     │                               │  1. Spawn worker              │
     │                               │ ─────────────────────────────>│
     │                               │                               │
     │                               │  2. GET /.well-known/agent.json
     │                               │ ─────────────────────────────>│
     │                               │                               │
     │                               │  Agent Card (capabilities)    │
     │                               │ <─────────────────────────────│
     │                               │                               │
     │                               │  3. POST /tasks/send          │
     │                               │  {task: "Build REST API"}     │
     │                               │ ─────────────────────────────>│
     │                               │                               │
     │                               │  4. SSE: task updates         │
     │                               │ <─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │
     │                               │     (streaming progress)      │
     │                               │                               │
     │  Progress updates             │                               │
     │ <─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │                               │
     │                               │                               │
     │                               │  5. Task completed            │
     │                               │  {artifacts: [files...]}      │
     │                               │ <─────────────────────────────│
     │                               │                               │
     │                               │  6. Terminate worker          │
     │                               │ ─────────────────────────────>│
     │                               │                               │
     │  Final result                 │                               │
     │ <─────────────────────────────│                               │
     │                               │                               │
```

### Real-time Streaming: A2A vs Claude Code Subagents

| Aspect | Claude Code `Task` tool | A2A Protocol |
|--------|------------------------|--------------|
| **Process model** | In-process subagent | Separate networked process |
| **Context sharing** | Full conversation history | Explicit message passing |
| **Communication** | Direct memory/IPC | HTTP + SSE streaming |
| **Streaming** | Token-by-token via parent | SSE events |
| **Isolation** | Same sandbox as parent | Separate sandbox per worker |
| **Scaling** | Single machine | Distributed across K8s |

### SSE (Server-Sent Events) Streaming Details

A2A uses SSE for real-time updates from worker to captain:

```
POST /tasks/send HTTP/1.1
Content-Type: application/json
Accept: text/event-stream

{"id": "task-123", "message": {"role": "user", "parts": [{"text": "Build API"}]}}

---

HTTP/1.1 200 OK
Content-Type: text/event-stream
Cache-Control: no-cache

event: task.status
data: {"id": "task-123", "status": "running"}

event: task.message
data: {"role": "assistant", "parts": [{"text": "Creating database models..."}]}

event: task.message
data: {"role": "assistant", "parts": [{"text": "Adding API routes..."}]}

event: task.artifact
data: {"name": "models.py", "mimeType": "text/x-python", "data": "base64..."}

event: task.artifact
data: {"name": "routes.py", "mimeType": "text/x-python", "data": "base64..."}

event: task.status
data: {"id": "task-123", "status": "completed", "artifacts": ["models.py", "routes.py"]}
```

### Captain: Real-time SSE Consumer

```python
# captain/a2a_client.py
import httpx
import json
from typing import AsyncIterator

class A2AClient:
    """Captain's client for communicating with workers via A2A"""

    def __init__(self, worker_url: str, auth_token: str = None):
        self.worker_url = worker_url
        self.headers = {"Authorization": f"Bearer {auth_token}"} if auth_token else {}

    async def discover(self) -> dict:
        """Get worker's agent card"""
        async with httpx.AsyncClient() as client:
            resp = await client.get(
                f"{self.worker_url}/.well-known/agent.json",
                headers=self.headers
            )
            return resp.json()

    async def send_task(self, task_id: str, message: str) -> AsyncIterator[dict]:
        """Send task and stream responses via SSE"""
        payload = {
            "id": task_id,
            "message": {
                "role": "user",
                "parts": [{"text": message}]
            }
        }

        async with httpx.AsyncClient() as client:
            async with client.stream(
                "POST",
                f"{self.worker_url}/tasks/send",
                json=payload,
                headers={**self.headers, "Accept": "text/event-stream"},
                timeout=None  # Long-running tasks
            ) as response:
                async for line in response.aiter_lines():
                    if line.startswith("data: "):
                        data = json.loads(line[6:])
                        yield data  # Stream each event to caller

    async def get_task(self, task_id: str) -> dict:
        """Get task status (non-streaming)"""
        async with httpx.AsyncClient() as client:
            resp = await client.get(
                f"{self.worker_url}/tasks/{task_id}",
                headers=self.headers
            )
            return resp.json()


# Usage in captain
async def execute_subtask(worker_url: str, task: str):
    client = A2AClient(worker_url)

    # Discover worker capabilities
    card = await client.discover()
    print(f"Worker skills: {[s['name'] for s in card['skills']]}")

    # Send task and stream progress
    async for event in client.send_task("task-123", task):
        match event.get("status"):
            case "running":
                print(f"⏳ Worker started...")
            case "completed":
                print(f"✅ Done! Artifacts: {event.get('artifacts', [])}")
                return event
            case "failed":
                print(f"❌ Failed: {event.get('error')}")
                raise Exception(event.get("error"))

        # Stream messages (like subagent output)
        if "parts" in event:
            for part in event["parts"]:
                if "text" in part:
                    print(f"  📝 {part['text']}")
```

### Worker: Real-time SSE Producer

```python
# worker/a2a_server.py
from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse
from sse_starlette.sse import EventSourceResponse
import asyncio
import subprocess
import os

app = FastAPI()

@app.get("/.well-known/agent.json")
async def agent_card():
    return {
        "name": "opencode-worker",
        "url": os.environ.get("WORKER_URL", "http://localhost:8080"),
        "skills": [{"id": "code", "name": "Code Generation"}],
        "capabilities": {"streaming": True}
    }

@app.post("/tasks/send")
async def send_task(request: Request):
    body = await request.json()
    task_id = body["id"]
    message = body["message"]["parts"][0]["text"]

    async def generate_events():
        # 1. Signal task started
        yield {"event": "task.status", "data": {"id": task_id, "status": "running"}}

        # 2. Run opencode and stream output
        process = await asyncio.create_subprocess_exec(
            "opencode", "--task", message,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
            cwd="/workspace"
        )

        # 3. Stream stdout as messages
        async for line in process.stdout:
            text = line.decode().strip()
            if text:
                yield {
                    "event": "task.message",
                    "data": {"role": "assistant", "parts": [{"text": text}]}
                }

        await process.wait()

        # 4. Collect artifacts (generated files)
        artifacts = []
        for f in os.listdir("/workspace"):
            if f.endswith((".py", ".js", ".ts", ".go")):
                artifacts.append({"name": f})

        # 5. Signal completion
        yield {
            "event": "task.status",
            "data": {
                "id": task_id,
                "status": "completed" if process.returncode == 0 else "failed",
                "artifacts": artifacts
            }
        }

    return EventSourceResponse(generate_events())

@app.get("/tasks/{task_id}")
async def get_task(task_id: str):
    # Return cached task status
    return {"id": task_id, "status": "completed"}
```

### Comparison: Subagent-style vs A2A

**Claude Code subagent (in-process):**
```python
# Parent agent calls subagent directly
result = await task_tool.run(
    prompt="Build a REST API",
    subagent_type="Explore"
)
# Blocks until done, streams via parent's connection
```

**A2A (networked, like microservices):**
```python
# Captain spawns isolated worker, communicates via HTTP+SSE
worker_url = await spawn_worker("task-123")
async for event in a2a_client.send_task(worker_url, "Build a REST API"):
    print(event)  # Real-time streaming via SSE
await terminate_worker("task-123")
```

**When to use which:**

| Use Case | Subagent (Task tool) | A2A (Captain/Worker) |
|----------|---------------------|---------------------|
| Quick exploration | ✅ | Overkill |
| Trusted code | ✅ | ✅ |
| Untrusted/sandboxed | ❌ | ✅ |
| Multi-machine | ❌ | ✅ |
| Different LLM providers | ❌ | ✅ |
| Long-running tasks | Timeout issues | ✅ (persistent workers) |
| Audit/compliance | Shared context | ✅ (isolated, logged) |

### Worker with A2A Endpoint (Python SDK)

```python
# worker/a2a_server.py
from a2a import A2AServer, AgentCard, Task, Message
import subprocess
import os

class OpenCodeWorker(A2AServer):
    def __init__(self):
        self.card = AgentCard(
            name="opencode-worker",
            description="Sandboxed OpenCode agent",
            skills=[
                {"id": "code-gen", "name": "Code Generation"},
                {"id": "code-review", "name": "Code Review"},
            ]
        )

    async def handle_task(self, task: Task) -> Task:
        """Execute task in sandboxed opencode"""
        workspace = os.environ.get("WORKSPACE", "/workspace")

        # Write task to file for opencode
        task_file = f"{workspace}/.task.md"
        with open(task_file, "w") as f:
            f.write(task.message.text)

        # Run opencode (already sandboxed by container/bwrap)
        result = subprocess.run(
            ["opencode", "--task", task_file],
            cwd=workspace,
            capture_output=True,
            text=True
        )

        # Return result
        task.status = "completed" if result.returncode == 0 else "failed"
        task.artifacts = self._collect_artifacts(workspace)
        return task

    def _collect_artifacts(self, workspace):
        # Collect generated files as artifacts
        # ...
        pass

if __name__ == "__main__":
    worker = OpenCodeWorker()
    worker.serve(port=8080)
```

### K8s Deployment with A2A

```yaml
# k8s/opencode-agent/deployment-a2a.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: opencode-worker
spec:
  replicas: 0  # Scale dynamically via captain
  template:
    spec:
      containers:
        # Main agent
        - name: agent
          image: ghcr.io/your-org/opencode-agent:latest
          env:
            - name: A2A_ENABLED
              value: "true"
          volumeMounts:
            - name: workspace
              mountPath: /workspace

        # A2A sidecar (exposes HTTP endpoint)
        - name: a2a-sidecar
          image: ghcr.io/your-org/a2a-sidecar:latest
          ports:
            - containerPort: 8080
              name: a2a
          env:
            - name: AGENT_SOCKET
              value: "/tmp/agent.sock"

      volumes:
        - name: workspace
          emptyDir: {}
---
# Service for A2A discovery
apiVersion: v1
kind: Service
metadata:
  name: opencode-worker
spec:
  selector:
    app: opencode-worker
  ports:
    - port: 8080
      name: a2a
```

### Captain Spawning Workers Dynamically

```bash
# Captain receives task, spawns worker
captain-agent spawn task-123

# Worker comes up, captain discovers it via A2A
curl http://worker-task-123.agents.svc:8080/.well-known/agent.json

# Captain sends task
curl -X POST http://worker-task-123.agents.svc:8080/tasks/send \
  -H "Content-Type: application/json" \
  -d '{
    "id": "task-123",
    "message": {
      "role": "user",
      "parts": [{"text": "Build a REST API for user management"}]
    }
  }'

# Captain polls for completion or uses SSE streaming
curl http://worker-task-123.agents.svc:8080/tasks/task-123

# Task done, captain terminates worker
captain-agent terminate task-123
```

### Security Considerations

| Concern | Mitigation |
|---------|------------|
| Captain compromise | Captain runs with minimal privileges, only K8s/systemd spawn rights |
| Worker escape | Workers are sandboxed (bwrap/container), can't affect captain |
| A2A auth | Bearer tokens between captain↔worker, mTLS in production |
| Network | Workers can only reach proxy, captain controls proxy allowlist |
| Resource exhaustion | Captain enforces limits per task, auto-terminates on TTL |

---

## OpenCode as Captain (Interactive Mode)

Use OpenCode/Claude Code as the captain in **real-time interactive mode** (not automation). The captain uses **MCP tools** to spawn and communicate with A2A workers.

### Why MCP + A2A?

| Protocol | Purpose | Direction |
|----------|---------|-----------|
| **MCP** | Human ↔ Captain tools | Captain calls tools to manage workers |
| **A2A** | Captain ↔ Workers | Workers expose A2A endpoints |

```
Human ←──(chat)──→ OpenCode ←──(MCP)──→ A2A Bridge ←──(A2A)──→ Workers
```

### MCP Server: A2A Worker Manager

```python
# mcp_servers/a2a_workers/server.py
"""
MCP Server that gives OpenCode/Claude Code the ability to:
- Spawn sandboxed workers
- Send tasks via A2A
- Stream real-time results back
- Terminate workers
"""

from mcp.server import Server
from mcp.types import Tool, TextContent
import httpx
import asyncio
import subprocess
import json
import os

app = Server("a2a-workers")

# Track active workers
workers: dict[str, dict] = {}


@app.tool()
async def spawn_worker(
    task_id: str,
    workspace: str = "/mnt/agents",
    config: dict = None
) -> str:
    """
    Spawn a new sandboxed worker agent.

    Args:
        task_id: Unique identifier for this worker
        workspace: Base directory for worker's files
        config: Optional worker configuration

    Returns:
        Worker URL for A2A communication
    """
    worker_workspace = f"{workspace}/{task_id}"
    os.makedirs(worker_workspace, exist_ok=True)

    # Create agent card
    card = {
        "agent_id": task_id,
        "workspace": worker_workspace,
        "proxy": config.get("proxy", "http://127.0.0.1:3128") if config else "http://127.0.0.1:3128",
        "a2a_port": 8080 + len(workers)  # Unique port per worker
    }

    card_path = f"/tmp/agent-cards/{task_id}.json"
    os.makedirs(os.path.dirname(card_path), exist_ok=True)
    with open(card_path, "w") as f:
        json.dump(card, f)

    # Spawn via systemd (or K8s)
    port = card["a2a_port"]

    # Option 1: Systemd
    proc = subprocess.Popen([
        "systemctl", "start", f"sandboxed-agent@{task_id}"
    ])

    # Option 2: Direct spawn (for development)
    # proc = subprocess.Popen([
    #     "agent-spawn", card_path
    # ])

    worker_url = f"http://127.0.0.1:{port}"
    workers[task_id] = {
        "url": worker_url,
        "card": card,
        "process": proc
    }

    # Wait for worker to be ready
    for _ in range(30):
        try:
            async with httpx.AsyncClient() as client:
                resp = await client.get(f"{worker_url}/.well-known/agent.json", timeout=1)
                if resp.status_code == 200:
                    return f"Worker spawned: {worker_url}\nCapabilities: {resp.json().get('skills', [])}"
        except:
            await asyncio.sleep(1)

    return f"Worker spawned but not yet responding: {worker_url}"


@app.tool()
async def send_task(
    task_id: str,
    message: str,
    stream: bool = True
) -> str:
    """
    Send a task to a worker and get the result.

    Args:
        task_id: Worker to send task to
        message: The task description/prompt
        stream: Whether to stream progress (default: True)

    Returns:
        Task result and any generated artifacts
    """
    if task_id not in workers:
        return f"Error: Worker {task_id} not found. Spawn it first."

    worker_url = workers[task_id]["url"]

    payload = {
        "id": f"task-{task_id}-{int(asyncio.get_event_loop().time())}",
        "message": {
            "role": "user",
            "parts": [{"text": message}]
        }
    }

    results = []

    async with httpx.AsyncClient() as client:
        async with client.stream(
            "POST",
            f"{worker_url}/tasks/send",
            json=payload,
            headers={"Accept": "text/event-stream"},
            timeout=None
        ) as response:
            async for line in response.aiter_lines():
                if line.startswith("data: "):
                    data = json.loads(line[6:])

                    # Collect messages for final result
                    if "parts" in data:
                        for part in data["parts"]:
                            if "text" in part:
                                results.append(part["text"])

                    # Check for completion
                    if data.get("status") == "completed":
                        artifacts = data.get("artifacts", [])
                        return f"Task completed!\n\nOutput:\n{''.join(results)}\n\nArtifacts: {artifacts}"

                    elif data.get("status") == "failed":
                        return f"Task failed: {data.get('error', 'Unknown error')}"

    return f"Task sent. Results:\n{''.join(results)}"


@app.tool()
async def get_worker_status(task_id: str) -> str:
    """
    Get the status of a worker.

    Args:
        task_id: Worker ID to check

    Returns:
        Worker status and recent activity
    """
    if task_id not in workers:
        return f"Worker {task_id} not found"

    worker_url = workers[task_id]["url"]

    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(f"{worker_url}/.well-known/agent.json", timeout=5)
            card = resp.json()
            return f"Worker {task_id} is running\nURL: {worker_url}\nSkills: {card.get('skills', [])}"
    except Exception as e:
        return f"Worker {task_id} not responding: {e}"


@app.tool()
async def terminate_worker(task_id: str) -> str:
    """
    Terminate a worker and clean up resources.

    Args:
        task_id: Worker to terminate

    Returns:
        Confirmation message
    """
    if task_id not in workers:
        return f"Worker {task_id} not found"

    # Stop via systemd
    subprocess.run(["systemctl", "stop", f"sandboxed-agent@{task_id}"])

    del workers[task_id]
    return f"Worker {task_id} terminated"


@app.tool()
async def list_workers() -> str:
    """
    List all active workers.

    Returns:
        List of worker IDs and their status
    """
    if not workers:
        return "No active workers"

    lines = ["Active workers:"]
    for task_id, info in workers.items():
        lines.append(f"  - {task_id}: {info['url']}")

    return "\n".join(lines)


if __name__ == "__main__":
    import mcp.server.stdio
    mcp.server.stdio.run(app)
```

### OpenCode/Claude Code Configuration

```json
// ~/.config/opencode/config.json (or Claude Code settings)
{
  "mcpServers": {
    "a2a-workers": {
      "command": "python",
      "args": ["/path/to/mcp_servers/a2a_workers/server.py"],
      "env": {
        "WORKERS_DIR": "/mnt/agents",
        "DEFAULT_PROXY": "http://127.0.0.1:3128"
      }
    }
  }
}
```

### Interactive Session Example

```
You: I need to build a REST API for user management with tests.

OpenCode: I'll spawn two workers - one for the API and one for tests.

[Calls spawn_worker(task_id="api-builder", workspace="/mnt/agents")]
→ Worker spawned: http://127.0.0.1:8080

[Calls spawn_worker(task_id="test-writer", workspace="/mnt/agents")]
→ Worker spawned: http://127.0.0.1:8081

[Calls send_task(task_id="api-builder", message="Build a REST API for user management with FastAPI. Include CRUD endpoints for users.")]
→ Streaming...
  📝 Creating project structure...
  📝 Writing models.py...
  📝 Writing routes.py...
  📝 Writing main.py...
→ Task completed! Artifacts: [models.py, routes.py, main.py]

[Calls send_task(task_id="test-writer", message="Write pytest tests for the API in /mnt/agents/api-builder")]
→ Streaming...
  📝 Reading API code...
  📝 Writing test_users.py...
→ Task completed! Artifacts: [test_users.py]

[Calls terminate_worker(task_id="api-builder")]
[Calls terminate_worker(task_id="test-writer")]
→ Workers terminated

OpenCode: Done! The API is in /mnt/agents/api-builder with tests in /mnt/agents/test-writer.
```

### Real-time Streaming to Human

The MCP tool returns intermediate results, so you see progress:

```
You: Build a complex microservice

OpenCode: [spawn_worker...]
         [send_task: "Build microservice..."]

         Worker progress:
         📝 Analyzing requirements...
         📝 Creating database schema...
         📝 Implementing service layer...
         📝 Adding API endpoints...
         📝 Writing Dockerfile...

         ✅ Complete! Files created:
         - src/models.py
         - src/services.py
         - src/api.py
         - Dockerfile
         - docker-compose.yml
```

### Comparison: Automation vs Interactive

| Mode | Captain | Trigger | Feedback |
|------|---------|---------|----------|
| **Interactive** | OpenCode CLI | You chat directly | Real-time in terminal |
| **Automation** | Script/API | GitHub issue, webhook | Async (PR, comment) |

### Benefits of Interactive Captain

1. **Real-time feedback** - See worker output as it happens
2. **Dynamic decisions** - Change approach mid-task based on results
3. **Multi-worker coordination** - Spawn workers for parallel subtasks
4. **Human-in-the-loop** - Review outputs before next step
5. **No infrastructure** - Just run OpenCode with MCP server

### NixOS Module for MCP Server

```nix
# modules/a2a-mcp-server/default.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.services.a2a-mcp-server;

  mcpServer = pkgs.python3Packages.buildPythonApplication {
    pname = "a2a-workers-mcp";
    version = "0.1.0";
    src = ./src;

    propagatedBuildInputs = with pkgs.python3Packages; [
      mcp
      httpx
      asyncio
    ];
  };

in {
  options.services.a2a-mcp-server = {
    enable = lib.mkEnableOption "A2A Workers MCP Server";

    workersDir = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/agents";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ mcpServer ];

    # Create MCP config for opencode
    environment.etc."opencode/mcp-servers.json".text = builtins.toJSON {
      a2a-workers = {
        command = "${mcpServer}/bin/a2a-workers-mcp";
        env = {
          WORKERS_DIR = cfg.workersDir;
        };
      };
    };
  };
}
```

### References

- [A2A Protocol Spec](https://a2a-protocol.org/latest/)
- [A2A GitHub](https://github.com/a2aproject/A2A)
- [A2A Python SDK](https://github.com/a2aproject/a2a-python)
- [Google ADK with A2A](https://developers.googleblog.com/en/a2a-a-new-era-of-agent-interoperability/)

---

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

## Part 0: Dynamic Runtime Sandboxing (Recommended)

**No rebuild required** - spawn/destroy agents at runtime with an "Agent ID Card".

### 0.1 Agent ID Card Concept

Each agent gets an identity card (JSON/TOML) that defines:

```json
{
  "agent_id": "agent-alpha-001",
  "workspace": "/mnt/agents/alpha-001",
  "api_provider": "anthropic",
  "api_key_file": "/run/secrets/agents/alpha-001/api-key",
  "proxy": "http://10.100.1.1:3128",
  "resource_limits": {
    "memory_mb": 4096,
    "cpu_shares": 1024,
    "max_processes": 50
  },
  "allowed_hosts": ["api.anthropic.com", "api.openai.com"],
  "ttl_seconds": 3600
}
```

### 0.2 Bubblewrap Launcher Script

```nix
# modules/opencode-sandbox/dynamic.nix
{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.programs.opencode-sandbox;

  # Minimal packages for the sandbox
  sandboxDeps = with pkgs; [
    dash
    coreutils
    git
    curl
    cacert
  ];

  opencode-pkg = inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.opencode;

  # Bubblewrap launcher that reads agent ID card
  agentLauncher = pkgs.writeShellScriptBin "opencode-spawn" ''
    set -euo pipefail

    CARD_FILE="''${1:-}"
    if [[ -z "$CARD_FILE" || ! -f "$CARD_FILE" ]]; then
      echo "Usage: opencode-spawn <agent-id-card.json>"
      exit 1
    fi

    # Parse agent card
    AGENT_ID=$(${pkgs.jq}/bin/jq -r '.agent_id' "$CARD_FILE")
    WORKSPACE=$(${pkgs.jq}/bin/jq -r '.workspace' "$CARD_FILE")
    API_KEY_FILE=$(${pkgs.jq}/bin/jq -r '.api_key_file // empty' "$CARD_FILE")
    PROXY=$(${pkgs.jq}/bin/jq -r '.proxy // "http://127.0.0.1:3128"' "$CARD_FILE")
    MEM_LIMIT=$(${pkgs.jq}/bin/jq -r '.resource_limits.memory_mb // 4096' "$CARD_FILE")
    TTL=$(${pkgs.jq}/bin/jq -r '.ttl_seconds // 0' "$CARD_FILE")

    # Validate workspace exists
    mkdir -p "$WORKSPACE"

    # Build API key argument
    API_KEY=""
    if [[ -n "$API_KEY_FILE" && -f "$API_KEY_FILE" ]]; then
      API_KEY=$(cat "$API_KEY_FILE")
    fi

    echo "[opencode-spawn] Starting agent: $AGENT_ID"
    echo "[opencode-spawn] Workspace: $WORKSPACE"
    echo "[opencode-spawn] Proxy: $PROXY"

    # Optional: timeout wrapper for TTL
    TIMEOUT_CMD=""
    if [[ "$TTL" -gt 0 ]]; then
      TIMEOUT_CMD="${pkgs.coreutils}/bin/timeout $TTL"
    fi

    # Launch with bubblewrap
    exec $TIMEOUT_CMD ${pkgs.bubblewrap}/bin/bwrap \
      --unshare-all \
      --share-net \
      --die-with-parent \
      --new-session \
      \
      `# Minimal root filesystem` \
      --tmpfs / \
      --dev /dev \
      --proc /proc \
      --tmpfs /tmp \
      \
      `# Read-only system paths` \
      --ro-bind /nix/store /nix/store \
      --ro-bind /etc/ssl/certs /etc/ssl/certs \
      --ro-bind /etc/resolv.conf /etc/resolv.conf \
      \
      `# Symlinks for FHS compatibility` \
      --symlink /nix/store/*-dash-*/bin/dash /bin/sh \
      --symlink ${pkgs.coreutils}/bin /usr/bin \
      \
      `# ONLY the agent workspace is writable` \
      --bind "$WORKSPACE" /workspace \
      \
      `# Block access to sensitive paths` \
      --tmpfs /home \
      --tmpfs /root \
      --tmpfs /mnt \
      --bind "$WORKSPACE" /mnt/workspace \
      \
      `# Environment` \
      --setenv HOME /workspace \
      --setenv OPENCODE_CONFIG_HOME /workspace/.config/opencode \
      --setenv SSL_CERT_FILE /etc/ssl/certs/ca-bundle.crt \
      --setenv HTTP_PROXY "$PROXY" \
      --setenv HTTPS_PROXY "$PROXY" \
      --setenv NO_PROXY "localhost,127.0.0.1" \
      --setenv AGENT_ID "$AGENT_ID" \
      ''${API_KEY:+--setenv ANTHROPIC_API_KEY "$API_KEY"} \
      \
      `# Chdir to workspace` \
      --chdir /workspace \
      \
      `# Run opencode` \
      ${opencode-pkg}/bin/opencode "''${@:2}"
  '';

  # Agent manager for listing/stopping agents
  agentManager = pkgs.writeShellScriptBin "opencode-agents" ''
    set -euo pipefail

    case "''${1:-}" in
      list)
        echo "Running opencode agents:"
        ${pkgs.procps}/bin/pgrep -af "opencode-spawn" || echo "  (none)"
        ;;
      stop)
        AGENT_ID="''${2:-}"
        if [[ -z "$AGENT_ID" ]]; then
          echo "Usage: opencode-agents stop <agent-id>"
          exit 1
        fi
        ${pkgs.procps}/bin/pkill -f "AGENT_ID=$AGENT_ID" && echo "Stopped $AGENT_ID" || echo "Agent not found"
        ;;
      *)
        echo "Usage: opencode-agents <list|stop <agent-id>>"
        ;;
    esac
  '';

in
{
  options.programs.opencode-sandbox = {
    enable = lib.mkEnableOption "Dynamic OpenCode sandbox launcher";

    agentsDir = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/agents";
      description = "Base directory for agent workspaces";
    };

    cardsDir = lib.mkOption {
      type = lib.types.str;
      default = "/etc/opencode-agents";
      description = "Directory for agent ID cards";
    };

    proxy = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:3128";
      description = "Default proxy for agents";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      agentLauncher
      agentManager
      pkgs.bubblewrap
      pkgs.jq
    ];

    # Create directories
    systemd.tmpfiles.rules = [
      "d ${cfg.agentsDir} 0755 root root -"
      "d ${cfg.cardsDir} 0750 root root -"
    ];
  };
}
```

### 0.3 Usage Examples

```bash
# Create an agent ID card
cat > /etc/opencode-agents/alpha-001.json << 'EOF'
{
  "agent_id": "alpha-001",
  "workspace": "/mnt/agents/alpha-001",
  "api_key_file": "/run/secrets/anthropic-key",
  "proxy": "http://10.100.1.1:3128",
  "resource_limits": { "memory_mb": 4096 },
  "ttl_seconds": 7200
}
EOF

# Spawn agent (no rebuild needed!)
opencode-spawn /etc/opencode-agents/alpha-001.json

# Spawn another agent
opencode-spawn /etc/opencode-agents/beta-002.json --some-flag

# List running agents
opencode-agents list

# Stop an agent
opencode-agents stop alpha-001
```

### 0.4 Systemd Template Unit (Alternative)

For better process management, use a systemd template:

```nix
# modules/opencode-sandbox/template.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.services.opencode-agent-template;
in
{
  options.services.opencode-agent-template.enable =
    lib.mkEnableOption "OpenCode agent systemd template";

  config = lib.mkIf cfg.enable {
    # Template unit: opencode-agent@.service
    # Start with: systemctl start opencode-agent@alpha-001
    systemd.services."opencode-agent@" = {
      description = "OpenCode Agent %i";
      after = [ "network.target" ];

      # %i is the instance name (agent ID)
      serviceConfig = {
        Type = "simple";
        ExecStart = "${agentLauncher}/bin/opencode-spawn /etc/opencode-agents/%i.json";
        Restart = "on-failure";
        RestartSec = "10s";

        # Systemd-level limits (defense in depth)
        MemoryMax = "4G";
        CPUQuota = "200%";
        TasksMax = 50;

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "opencode-%i";
      };
    };
  };
}
```

**Usage:**
```bash
# Create agent card
echo '{"agent_id":"dev-agent","workspace":"/mnt/agents/dev"}' > /etc/opencode-agents/dev-agent.json

# Start/stop via systemd (no rebuild!)
systemctl start opencode-agent@dev-agent
systemctl stop opencode-agent@dev-agent
systemctl status opencode-agent@dev-agent
journalctl -u opencode-agent@dev-agent -f
```

### 0.5 Network Namespace Isolation (Optional)

For stronger network isolation, create per-agent network namespaces:

```nix
# Enhanced launcher with network namespace
agentLauncherNetns = pkgs.writeShellScriptBin "opencode-spawn-isolated" ''
  AGENT_ID="$1"
  NETNS="agent-$AGENT_ID"

  # Create network namespace with only proxy access
  ${pkgs.iproute2}/bin/ip netns add "$NETNS" 2>/dev/null || true

  # Create veth pair
  ${pkgs.iproute2}/bin/ip link add "veth-$AGENT_ID" type veth peer name "veth-$AGENT_ID-ns"
  ${pkgs.iproute2}/bin/ip link set "veth-$AGENT_ID-ns" netns "$NETNS"

  # Configure IPs (each agent gets unique subnet)
  SUBNET=$((100 + RANDOM % 150))
  ${pkgs.iproute2}/bin/ip addr add "10.$SUBNET.0.1/24" dev "veth-$AGENT_ID"
  ${pkgs.iproute2}/bin/ip netns exec "$NETNS" ip addr add "10.$SUBNET.0.2/24" dev "veth-$AGENT_ID-ns"
  ${pkgs.iproute2}/bin/ip netns exec "$NETNS" ip link set lo up
  ${pkgs.iproute2}/bin/ip netns exec "$NETNS" ip link set "veth-$AGENT_ID-ns" up
  ${pkgs.iproute2}/bin/ip link set "veth-$AGENT_ID" up

  # Route only to proxy (iptables on host controls this)
  ${pkgs.iproute2}/bin/ip netns exec "$NETNS" ip route add default via "10.$SUBNET.0.1"

  # Run bwrap inside the namespace
  ${pkgs.iproute2}/bin/ip netns exec "$NETNS" ${agentLauncher}/bin/opencode-spawn "$@"

  # Cleanup on exit
  trap "${pkgs.iproute2}/bin/ip netns del '$NETNS' 2>/dev/null" EXIT
'';
```

### 0.6 Agent Card Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "OpenCode Agent ID Card",
  "type": "object",
  "required": ["agent_id", "workspace"],
  "properties": {
    "agent_id": {
      "type": "string",
      "pattern": "^[a-z0-9-]+$",
      "description": "Unique identifier for this agent"
    },
    "workspace": {
      "type": "string",
      "description": "Absolute path to agent's working directory"
    },
    "api_provider": {
      "type": "string",
      "enum": ["anthropic", "openai", "ollama", "custom"],
      "default": "anthropic"
    },
    "api_key_file": {
      "type": "string",
      "description": "Path to file containing API key"
    },
    "proxy": {
      "type": "string",
      "format": "uri",
      "default": "http://127.0.0.1:3128"
    },
    "resource_limits": {
      "type": "object",
      "properties": {
        "memory_mb": { "type": "integer", "default": 4096 },
        "cpu_shares": { "type": "integer", "default": 1024 },
        "max_processes": { "type": "integer", "default": 50 },
        "max_open_files": { "type": "integer", "default": 1024 }
      }
    },
    "allowed_hosts": {
      "type": "array",
      "items": { "type": "string" },
      "description": "Hostnames agent is allowed to connect to (via proxy)"
    },
    "ttl_seconds": {
      "type": "integer",
      "default": 0,
      "description": "Auto-terminate after N seconds (0 = no limit)"
    },
    "environment": {
      "type": "object",
      "additionalProperties": { "type": "string" },
      "description": "Additional environment variables"
    }
  }
}
```

---

## Part 1: NixOS Systemd Service (Static Option)

For static deployment without K3s, use heavy systemd sandboxing.

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

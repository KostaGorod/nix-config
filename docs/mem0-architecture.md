# Mem0 Architecture Patterns

This document captures three deployment patterns for Mem0 AI memory layer in NixOS. Use this to select the appropriate pattern without re-analyzing the codebase.

## Quick Decision Matrix

| Requirement | Pattern A (Embedded) | Pattern B (Podman) | Pattern C (K3s) |
|-------------|---------------------|-------------------|-----------------|
| Single workstation | ✅ Ideal | ⚠️ Overkill | ❌ Way overkill |
| Multiple nodes sharing memory | ❌ Not possible | ✅ Yes | ✅ Yes |
| Minimal moving parts | ✅ One service | ⚠️ Two services | ❌ Many services |
| Data survives mem0 crashes | ❌ Risk | ✅ Yes | ✅ Yes |
| Qdrant dashboard/debugging | ❌ No | ✅ Yes | ✅ Yes |
| Offline/air-gapped | ⚠️ Needs uvx cache | ⚠️ Needs uvx cache | ✅ Full image cache |
| Container infrastructure | ❌ Not needed | ✅ Podman | ✅ K3s + containerd |
| Auto-healing/restart | ⚠️ Systemd only | ⚠️ Systemd only | ✅ Kubernetes |
| Rolling updates | ❌ Manual | ❌ Manual | ✅ Native |
| Resource limits/quotas | ⚠️ Systemd cgroups | ⚠️ Podman limits | ✅ Native |
| GPU workloads (Ollama) | ❌ Complex | ⚠️ Possible | ✅ Device plugin ready |
| Secrets management | ✅ agenix | ✅ agenix | ✅ K8s secrets + agenix |
| Horizontal scaling | ❌ No | ❌ Manual | ✅ HPA/replicas |
| Service mesh/mTLS | ❌ No | ❌ No | ✅ Optional |
| GitOps deployment | ❌ No | ❌ No | ✅ Flux/ArgoCD |

---

## Dev Time Estimates (Migration Paths)

| Migration Path | Effort | Prerequisites | Risk |
|----------------|--------|---------------|------|
| A → B (Embedded → Podman) | **2-4 hours** | Podman enabled | Low |
| A → C (Embedded → K3s) | **8-16 hours** | K3s cluster, storage class | Medium |
| B → C (Podman → K3s) | **4-8 hours** | K3s cluster, storage class | Low |
| New → A | **30 min** | None | None |
| New → B | **1-2 hours** | Podman enabled | Low |
| New → C | **8-16 hours** | Full K3s setup | Medium |

### What's Included in Each Estimate

**A → B (2-4 hours):**
- Enable podman (5 min)
- Deploy qdrant.nix module (15 min)
- Deploy mem0-simple.nix module (15 min)
- Data migration if needed (30 min)
- Testing and validation (1-2 hours)

**B → C (4-8 hours):**
- Write K8s manifests for Qdrant (1-2 hours)
- Write K8s manifests for Mem0 (1-2 hours)
- Configure PersistentVolume for Qdrant (1 hour)
- Configure secrets (30 min)
- Configure ingress/service exposure (1 hour)
- Testing and validation (1-2 hours)

**A → C (8-16 hours):**
- All of B → C work, plus:
- K3s cluster setup if not done (2-4 hours)
- Storage class configuration (1-2 hours)
- Ingress controller setup (1-2 hours)

### Current K3s Infrastructure Status (gpu-node-1)

| Component | Status | Gap to Close |
|-----------|--------|--------------|
| K3s server | ✅ Running | None |
| GPU support | ✅ NVIDIA device plugin | None |
| Flannel networking | ✅ VXLAN | None |
| Ingress controller | ❌ Disabled | Need MetalLB or Traefik |
| Storage class | ❌ Missing | Need local-path or NFS |
| Helm | ❌ Not configured | Optional |
| Flux/ArgoCD | ❌ Not configured | Optional |

**If deploying mem0 to existing K3s:** Add 2-4 hours for storage class setup.

---

## Pattern A: Embedded Qdrant (Current)

### Architecture

```
┌─────────────────────────────────────────┐
│  Host (rocinante)                       │
├─────────────────────────────────────────┤
│  ┌───────────────────────────────────┐  │
│  │  mem0-mcp (systemd service)       │  │
│  │  ├── Embedded Qdrant (in-process) │  │
│  │  └── Data: /var/lib/mem0/qdrant/  │  │
│  └───────────────────────────────────┘  │
│              │                          │
│              ▼                          │
│  ┌─────────────────┐  ┌──────────────┐  │
│  │ VoyageAI API    │  │ Anthropic API│  │
│  │ (embeddings)    │  │ (extraction) │  │
│  └─────────────────┘  └──────────────┘  │
└─────────────────────────────────────────┘
```

### Module

**File:** `modules/nixos/mem0.nix` (212 lines)

### Configuration

```nix
# In host configuration.nix
imports = [ ../../modules/nixos/mem0.nix ];

# User-level tools (optional, for CLI usage)
programs.mem0 = {
  enable = true;
  selfHosted = true;
  userId = "kosta";
};

# Systemd service
services.mem0 = {
  enable = true;
  port = 8050;
  userId = "kosta";

  embedder = {
    provider = "voyageai";
    model = "voyage-4-lite";
    apiKeyFile = "/run/secrets/voyage-api-key";
  };

  llm = {
    provider = "anthropic";
    model = "claude-sonnet-4-20250514";
    apiKeyFile = "/run/secrets/anthropic-api-key";
  };
};
```

### Data Locations

| Purpose | Path |
|---------|------|
| Service vector data | `/var/lib/mem0/qdrant/` |
| User vector data | `~/.local/share/mem0/qdrant/` |
| Config cache | `~/.config/mem0/` |

### Pros

- **Simpler deployment**: Single service, no container runtime
- **Lower resource usage**: No separate Qdrant process
- **Faster initial setup**: Just enable the service
- **Good for single user**: Personal workstation use

### Cons

- **No HA**: Cannot share memory across nodes
- **Data coupling**: Qdrant data tied to mem0 process lifecycle
- **No observability**: Cannot inspect vectors directly
- **Dual config pattern**: `programs.mem0` + `services.mem0` overlap

### Practical Use Cases

1. **Personal developer workstation**
   - Single machine running Claude Code/OpenCode
   - Memory is personal, not shared
   - Example: laptop (rocinante)

2. **Isolated development environments**
   - Each developer has own mem0 instance
   - No cross-pollination of memories needed

3. **Quick prototyping**
   - Testing mem0 before committing to infrastructure
   - Evaluating if AI memory is useful for workflow

---

## Pattern B: External Qdrant (New/Recommended for HA)

### Architecture

```
┌─────────────────────────┐     ┌─────────────────────────┐
│  Node 1 (rocinante)     │     │  Node 2 (gpu-node-1)    │
├─────────────────────────┤     ├─────────────────────────┤
│  mem0-mcp               │     │  mem0-mcp               │
│  (stateless)            │     │  (stateless)            │
└──────────┬──────────────┘     └──────────┬──────────────┘
           │                               │
           └───────────┬───────────────────┘
                       ▼
         ┌─────────────────────────────────┐
         │  Qdrant Container               │
         │  ├── Port 6333 (HTTP API)       │
         │  ├── Port 6334 (gRPC)           │
         │  ├── Port 6335 (cluster P2P)    │
         │  └── /var/lib/qdrant/storage/   │
         └─────────────────────────────────┘
                       │
           ┌───────────┴───────────┐
           ▼                       ▼
   ┌──────────────┐        ┌──────────────┐
   │ VoyageAI API │        │ Anthropic API│
   └──────────────┘        └──────────────┘
```

### Modules

**Files:**
- `modules/nixos/mem0-simple.nix` (138 lines) - Mem0 service
- `modules/nixos/qdrant.nix` (95 lines) - Qdrant container

### Configuration

```nix
# In host configuration.nix
imports = [
  ../../modules/nixos/qdrant.nix
  ../../modules/nixos/mem0-simple.nix
];

# Qdrant vector database
services.qdrant = {
  enable = true;
  # Default: localhost:6333
  # For multi-node: host = "0.0.0.0"; openFirewall = true;
};

# Mem0 service (points to Qdrant)
services.mem0 = {
  enable = true;
  port = 8050;
  userId = "kosta";
  qdrant.url = "http://localhost:6333";  # Or remote Qdrant

  embedder = {
    provider = "voyageai";
    model = "voyage-4-lite";
    apiKeyFile = "/run/secrets/voyage-api-key";
  };

  llm = {
    provider = "anthropic";
    model = "claude-sonnet-4-20250514";
    apiKeyFile = "/run/secrets/anthropic-api-key";
  };
};
```

### Multi-Node Configuration

**Node hosting Qdrant (e.g., gpu-node-1):**
```nix
services.qdrant = {
  enable = true;
  host = "0.0.0.0";        # Listen on all interfaces
  openFirewall = true;      # Allow 6333, 6334

  # Optional: cluster mode for HA
  # cluster.enable = true;
};

services.mem0 = {
  enable = true;
  qdrant.url = "http://localhost:6333";
  # ... embedder/llm config
};
```

**Remote nodes (e.g., rocinante):**
```nix
# No Qdrant service - uses remote

services.mem0 = {
  enable = true;
  qdrant.url = "http://gpu-node-1:6333";  # Tailscale hostname
  # ... embedder/llm config
};
```

### Data Locations

| Purpose | Path | Container |
|---------|------|-----------|
| Vector storage | `/var/lib/qdrant/storage/` | Mounted |
| Snapshots | `/var/lib/qdrant/snapshots/` | Mounted |
| Mem0 state | `/var/lib/mem0/` | N/A |

### Qdrant Management

```bash
# Check Qdrant health
curl http://localhost:6333/health

# Open dashboard
xdg-open http://localhost:6333/dashboard

# List collections
curl http://localhost:6333/collections

# Get collection info (mem0 default collection)
curl http://localhost:6333/collections/mem0

# Create snapshot for backup
curl -X POST http://localhost:6333/collections/mem0/snapshots

# Container logs
journalctl -u podman-qdrant -f
```

### Pros

- **HA-ready**: Multiple mem0 instances share one Qdrant
- **Data isolation**: Qdrant survives mem0 restarts/crashes
- **Observable**: Dashboard at `http://host:6333/dashboard`
- **Scalable**: Qdrant cluster mode for replication
- **Backup-friendly**: Snapshot API for backups
- **Clean separation**: Mem0 is stateless, Qdrant is stateful

### Cons

- **More infrastructure**: Requires podman and container management
- **Resource overhead**: Separate Qdrant process (~200MB RAM)
- **Network dependency**: Mem0 needs Qdrant to be reachable
- **Complexity**: Two services to manage instead of one

### Practical Use Cases

1. **Multi-machine development**
   - Laptop + desktop sharing memories
   - Start conversation on laptop, continue on desktop
   - Memory follows the user, not the machine

2. **Team shared memory**
   - Engineering team shares learned patterns
   - Onboarding: new devs inherit team knowledge
   - Example: "How do we deploy X?" answered from team memory

3. **CI/CD integration**
   - Build agents access shared memory
   - Remember past build failures and fixes
   - Cross-project pattern learning

4. **High-availability production**
   - Qdrant cluster across availability zones
   - Mem0 instances are stateless, easily replaceable
   - Zero-downtime updates

5. **Debugging/auditing**
   - Qdrant dashboard shows stored vectors
   - Can inspect what memories exist
   - Delete/modify memories directly if needed

---

## Pattern C: Kubernetes (K3s)

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│  K3s Cluster (gpu-node-1 + future nodes)                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  Namespace: mem0                                                │    │
│  │                                                                 │    │
│  │  ┌─────────────────┐      ┌─────────────────────────────────┐   │    │
│  │  │ Deployment:     │      │ StatefulSet: qdrant             │   │    │
│  │  │ mem0-mcp        │      │ ├── Replicas: 1 (or 3 for HA)   │   │    │
│  │  │ ├── Replicas: 2 │──────│ ├── PVC: qdrant-data (10Gi)     │   │    │
│  │  │ └── Stateless   │      │ └── Service: qdrant:6333        │   │    │
│  │  └─────────────────┘      └─────────────────────────────────┘   │    │
│  │           │                              │                      │    │
│  │           ▼                              ▼                      │    │
│  │  ┌─────────────────┐      ┌─────────────────────────────────┐   │    │
│  │  │ Service:        │      │ Optional: ollama (GPU)          │   │    │
│  │  │ mem0:8050       │      │ ├── nvidia.com/gpu: 1           │   │    │
│  │  └─────────────────┘      │ └── Local embeddings/LLM        │   │    │
│  │                           └─────────────────────────────────┘   │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  Ingress (Traefik/MetalLB)                                       │   │
│  │  └── mem0.local:80 → mem0:8050                                   │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
      ┌──────────────┐               ┌──────────────┐
      │ VoyageAI API │               │ Anthropic API│
      │ (or Ollama)  │               │ (or Ollama)  │
      └──────────────┘               └──────────────┘
```

### What K3s Adds Over Podman

| Capability | Podman | K3s | Business Value |
|------------|--------|-----|----------------|
| **Self-healing** | Systemd restart | Pod recreation + rescheduling | Less manual intervention |
| **Rolling updates** | Manual stop/start | Zero-downtime deploys | No service interruption |
| **Horizontal scaling** | Manual container duplication | `replicas: N` or HPA | Handle load spikes |
| **Resource governance** | Per-container limits | Namespace quotas, LimitRanges | Multi-tenant safety |
| **Service discovery** | Manual DNS/hosts | CoreDNS automatic | Services find each other |
| **Load balancing** | Manual nginx/haproxy | Built-in Service LB | Automatic traffic distribution |
| **Secrets rotation** | Manual file updates | K8s secrets + operators | Automated key rotation |
| **GPU scheduling** | Manual `--gpus` | NVIDIA device plugin | Automatic GPU allocation |
| **Storage abstraction** | Bind mounts | PVC/StorageClass | Portable across nodes |
| **GitOps** | Not possible | Flux/ArgoCD | Declarative, auditable |
| **Multi-node** | Tailscale + manual | Native clustering | Automatic pod placement |

### Practical Use Cases for K3s

1. **AI/ML Platform with GPU Sharing**
   - Multiple AI agents (mem0, ollama, opencode) share RTX 2070
   - K3s schedules based on GPU availability
   - GPU Arbiter integration for gaming VM switching
   - Example: mem0 uses Ollama for local embeddings when GPU available

2. **Production-Grade Shared Memory**
   - Qdrant StatefulSet with 3 replicas (HA)
   - Automatic failover if node dies
   - Rolling updates without downtime
   - PVC snapshots for backup

3. **Multi-Agent Orchestration**
   - OpenCode agents in sandboxed pods
   - mem0 provides shared memory across agents
   - Network policies isolate agent namespaces
   - Resource quotas prevent runaway agents

4. **GitOps-Managed Infrastructure**
   - All mem0/qdrant configs in Git
   - Flux auto-deploys on push
   - Easy rollback via git revert
   - Audit trail of all changes

5. **Hybrid Cloud Burst**
   - Local K3s for normal load
   - Burst to cloud K8s for heavy workloads
   - Same manifests work everywhere
   - Qdrant Cloud as external backend

### When NOT to Use K3s

- **Single laptop user**: Pattern A is simpler
- **Two nodes, simple sharing**: Pattern B is enough
- **No GPU workloads**: K3s GPU value is wasted
- **Time-constrained**: 8-16 hours setup vs 2-4 hours for Pattern B
- **Learning curve aversion**: K8s concepts required

### Configuration (K3s Manifests)

**File:** `modules/k3s/manifests/mem0/` (to be created)

```yaml
# namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: mem0
---
# qdrant-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: qdrant-data
  namespace: mem0
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 10Gi
  storageClassName: local-path  # Requires local-path-provisioner
---
# qdrant-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: qdrant
  namespace: mem0
spec:
  serviceName: qdrant
  replicas: 1
  selector:
    matchLabels:
      app: qdrant
  template:
    metadata:
      labels:
        app: qdrant
    spec:
      containers:
      - name: qdrant
        image: qdrant/qdrant:v1.13.2
        ports:
        - containerPort: 6333
        - containerPort: 6334
        volumeMounts:
        - name: data
          mountPath: /qdrant/storage
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
        livenessProbe:
          httpGet:
            path: /health
            port: 6333
          initialDelaySeconds: 10
        readinessProbe:
          httpGet:
            path: /readyz
            port: 6333
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: qdrant-data
---
# qdrant-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: qdrant
  namespace: mem0
spec:
  ports:
  - port: 6333
    name: http
  - port: 6334
    name: grpc
  selector:
    app: qdrant
---
# mem0-secret.yaml (use with agenix or sealed-secrets)
apiVersion: v1
kind: Secret
metadata:
  name: mem0-api-keys
  namespace: mem0
type: Opaque
stringData:
  VOYAGE_API_KEY: "${VOYAGE_API_KEY}"      # Injected from agenix
  ANTHROPIC_API_KEY: "${ANTHROPIC_API_KEY}" # Injected from agenix
---
# mem0-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mem0
  namespace: mem0
spec:
  replicas: 1  # Can scale horizontally
  selector:
    matchLabels:
      app: mem0
  template:
    metadata:
      labels:
        app: mem0
    spec:
      containers:
      - name: mem0-mcp
        image: ghcr.io/mem0ai/mem0-mcp:latest  # Or build custom
        ports:
        - containerPort: 8050
        env:
        - name: MEM0_QDRANT_URL
          value: "http://qdrant:6333"
        - name: MEM0_DEFAULT_USER_ID
          value: "kosta"
        - name: MEM0_EMBEDDER_PROVIDER
          value: "voyageai"
        - name: MEM0_EMBEDDER_MODEL
          value: "voyage-4-lite"
        - name: MEM0_LLM_PROVIDER
          value: "anthropic"
        - name: MEM0_LLM_MODEL
          value: "claude-sonnet-4-20250514"
        envFrom:
        - secretRef:
            name: mem0-api-keys
        resources:
          requests:
            memory: "128Mi"
            cpu: "50m"
          limits:
            memory: "512Mi"
            cpu: "500m"
---
# mem0-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: mem0
  namespace: mem0
spec:
  ports:
  - port: 8050
  selector:
    app: mem0
```

### NixOS Integration for K3s

```nix
# In modules/k3s/server.nix (extend existing)
{
  # Deploy mem0 manifests via NixOS
  environment.etc."rancher/k3s/server/manifests/mem0-namespace.yaml".source =
    ./manifests/mem0/namespace.yaml;
  environment.etc."rancher/k3s/server/manifests/mem0-qdrant.yaml".source =
    ./manifests/mem0/qdrant.yaml;
  environment.etc."rancher/k3s/server/manifests/mem0-deployment.yaml".source =
    ./manifests/mem0/deployment.yaml;

  # Inject secrets from agenix into K8s (one-time setup)
  systemd.services.mem0-k8s-secrets = {
    description = "Sync agenix secrets to K8s";
    wantedBy = [ "multi-user.target" ];
    after = [ "k3s.service" ];
    script = ''
      kubectl create secret generic mem0-api-keys \
        --from-file=VOYAGE_API_KEY=/run/secrets/voyage-api-key \
        --from-file=ANTHROPIC_API_KEY=/run/secrets/anthropic-api-key \
        --namespace=mem0 \
        --dry-run=client -o yaml | kubectl apply -f -
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };
}
```

### Pros

- **True HA**: Pod rescheduling, StatefulSet guarantees
- **GPU-native**: NVIDIA device plugin already configured
- **Scalable**: Horizontal scaling with HPA
- **Observable**: Built-in metrics, ready for Prometheus
- **GitOps-ready**: Flux/ArgoCD integration possible
- **Portable**: Same manifests work on any K8s
- **Resource isolation**: Namespaces, quotas, network policies

### Cons

- **Complexity**: Significant learning curve
- **Setup time**: 8-16 hours vs 2-4 for Pattern B
- **Resource overhead**: K3s uses ~500MB RAM baseline
- **Debugging**: kubectl + pod logs vs simple journalctl
- **Overkill for 2 nodes**: Most benefits appear at 3+ nodes
- **Missing infrastructure**: Need storage class, ingress setup first

### Migration Path: Pattern B → Pattern C

1. **Prerequisites (2-4 hours)**
   ```bash
   # Install local-path-provisioner for PVCs
   kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml

   # Verify storage class
   kubectl get storageclass
   ```

2. **Create namespace and secrets (30 min)**
   ```bash
   kubectl create namespace mem0
   kubectl create secret generic mem0-api-keys \
     --from-file=VOYAGE_API_KEY=/run/secrets/voyage-api-key \
     --from-file=ANTHROPIC_API_KEY=/run/secrets/anthropic-api-key \
     -n mem0
   ```

3. **Export Qdrant data from Podman (30 min)**
   ```bash
   # Create snapshot in Podman Qdrant
   curl -X POST http://localhost:6333/collections/mem0/snapshots

   # Copy snapshot to PVC location
   cp /var/lib/qdrant/snapshots/* /var/lib/rancher/k3s/storage/qdrant-data/snapshots/
   ```

4. **Apply manifests (15 min)**
   ```bash
   kubectl apply -f modules/k3s/manifests/mem0/
   ```

5. **Restore data and verify (1 hour)**
   ```bash
   # Restore snapshot in K3s Qdrant
   kubectl exec -n mem0 qdrant-0 -- \
     curl -X PUT http://localhost:6333/collections/mem0/snapshots/recover \
     -H "Content-Type: application/json" \
     -d '{"location": "/qdrant/snapshots/<snapshot-name>"}'

   # Verify
   kubectl get pods -n mem0
   curl http://mem0.local:8050/health
   ```

6. **Disable Podman services (15 min)**
   ```nix
   services.qdrant.enable = false;
   services.mem0.enable = false;  # If using Pattern B module
   ```

---

## Migration: Pattern A → Pattern B

### Prerequisites

- Podman available (`virtualisation.podman.enable = true`)
- Network access between nodes (Tailscale recommended)

### Steps

1. **Deploy Qdrant first**
   ```nix
   services.qdrant.enable = true;
   ```
   ```bash
   sudo nixos-rebuild switch
   curl http://localhost:6333/health  # Verify
   ```

2. **Migrate existing data** (optional, if preserving memories)
   ```bash
   # Stop old mem0
   sudo systemctl stop mem0

   # Copy embedded Qdrant data to new location
   sudo cp -r /var/lib/mem0/qdrant/* /var/lib/qdrant/storage/

   # Fix permissions
   sudo chown -R root:root /var/lib/qdrant/
   ```

3. **Switch to new module**
   ```nix
   imports = [
     # ../../modules/nixos/mem0.nix  # Remove old
     ../../modules/nixos/qdrant.nix
     ../../modules/nixos/mem0-simple.nix
   ];

   # Remove old programs.mem0 config
   # Update services.mem0 config (see Pattern B above)
   ```

4. **Rebuild and verify**
   ```bash
   sudo nixos-rebuild switch
   systemctl status qdrant mem0
   curl http://localhost:8050/health
   ```

---

## API Keys Reference

Both patterns use the same API keys via agenix:

| Secret | Environment Variable | Provider |
|--------|---------------------|----------|
| `/run/secrets/voyage-api-key` | `VOYAGE_API_KEY` | VoyageAI embeddings |
| `/run/secrets/anthropic-api-key` | `ANTHROPIC_API_KEY` | Anthropic LLM |

### Alternative Providers

| Component | Provider | Model | Notes |
|-----------|----------|-------|-------|
| Embeddings | VoyageAI | `voyage-4-lite` | Fast, cost-effective |
| Embeddings | VoyageAI | `voyage-code-3` | Code-optimized |
| Embeddings | OpenAI | `text-embedding-3-small` | Requires OpenAI key |
| Embeddings | Ollama | `nomic-embed-text` | Fully local |
| LLM | Anthropic | `claude-sonnet-4-20250514` | Best extraction |
| LLM | OpenAI | `gpt-4.1-nano-2025-04-14` | Alternative |
| LLM | Ollama | `llama3.2` | Fully local |

---

## MCP Client Configuration

Same for both patterns - just point to the mem0 service:

**Claude Code:**
```bash
claude mcp add mem0 --transport sse --url http://localhost:8050/sse
```

**OpenCode:** (`~/.config/opencode/opencode.json`)
```json
{
  "mcp": {
    "mem0": {
      "transport": "sse",
      "url": "http://localhost:8050/sse"
    }
  }
}
```

For remote mem0 (Pattern B multi-node):
```bash
claude mcp add mem0 --transport sse --url http://gpu-node-1:8050/sse
```

---

## Troubleshooting

### Pattern A Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Service fails to start | uvx can't download mem0-mcp | Check network, retry |
| "Qdrant not initialized" | First run, needs time | Wait 30s, restart |
| High memory usage | Qdrant in-process | Normal, ~500MB+ |

### Pattern B Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Connection refused" to Qdrant | Container not running | `systemctl start podman-qdrant` |
| mem0 starts before Qdrant | Race condition | Service has `After=qdrant.service` |
| "Permission denied" on /var/lib/qdrant | Volume permissions | `chown -R root:root /var/lib/qdrant` |
| Qdrant unhealthy | Resource exhaustion | Check `podman logs qdrant` |

### Common to Both

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Invalid API key" | Wrong key file | Check `/run/secrets/` permissions |
| Embeddings fail | VoyageAI rate limit | Wait or upgrade plan |
| Memory extraction slow | LLM latency | Normal for large contexts |

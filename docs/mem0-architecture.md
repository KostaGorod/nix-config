# Mem0 Architecture Patterns

This document captures two deployment patterns for Mem0 AI memory layer in NixOS. Use this to select the appropriate pattern without re-analyzing the codebase.

## Quick Decision Matrix

| Requirement | Pattern A (Embedded) | Pattern B (External Qdrant) |
|-------------|---------------------|----------------------------|
| Single workstation | ✅ Ideal | ⚠️ Overkill |
| Multiple nodes sharing memory | ❌ Not possible | ✅ Required |
| Minimal moving parts | ✅ One service | ❌ Two services |
| Data survives mem0 crashes | ❌ Risk | ✅ Yes |
| Qdrant dashboard/debugging | ❌ No | ✅ Yes (port 6333) |
| Offline/air-gapped | ⚠️ Needs uvx cache | ⚠️ Needs uvx cache |
| Container infrastructure | ❌ Not needed | ✅ Requires podman |

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

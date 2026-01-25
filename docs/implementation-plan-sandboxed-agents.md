# Implementation Plan: Sandboxed Agents

## Security Review Summary

**Critical findings requiring immediate fix:**
- MCP server runs with host privileges → privilege separation needed
- Captain has unrestricted systemd access → dedicated spawner daemon
- `--share-net` allows proxy bypass → network namespace isolation
- Proxy allows all domains → domain allowlist enforcement
- No input validation → task_id injection possible

**Total findings**: 25 (2 Critical, 10 High, 10 Medium, 3 Low)

---

## Design Principles

1. **Incremental**: Each phase produces a working, secure system
2. **Testable**: Every phase has specific test cases
3. **Not broken until done**: No phase leaves security holes

---

## Phase 0: Foundation (Testable Standalone)

**Goal**: Minimal secure sandbox that can run opencode with verified isolation.

### 0.1 Create Restricted Spawner Daemon

Instead of MCP server calling systemd directly, create a dedicated daemon with limited capabilities.

```
┌──────────────────┐         Unix Socket         ┌──────────────────┐
│  MCP Server      │◄───────────────────────────►│  agent-spawner   │
│  (unprivileged)  │    (restricted protocol)    │  (root, locked)  │
└──────────────────┘                             └──────────────────┘
```

**Files to create:**

```
modules/agent-spawner/
├── daemon.py           # Privileged spawner with restricted API
├── client.py           # Unprivileged client library
├── default.nix         # NixOS module
└── tests/
    ├── test_spawn.py
    ├── test_validation.py
    └── test_isolation.py
```

**Implementation:**

```nix
# modules/agent-spawner/default.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.services.agent-spawner;

  spawnerDaemon = pkgs.python3Packages.buildPythonApplication {
    pname = "agent-spawner";
    version = "0.1.0";
    src = ./src;
    # ...
  };

in {
  options.services.agent-spawner = {
    enable = lib.mkEnableOption "Secure agent spawner daemon";

    maxWorkers = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Maximum concurrent workers";
    };

    allowedWorkspaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "/mnt/agents" ];
      description = "Directories where workers can have workspaces";
    };

    spawnCooldownSeconds = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "Minimum seconds between spawns";
    };
  };

  config = lib.mkIf cfg.enable {
    # Dedicated user for spawner daemon
    users.users.agent-spawner = {
      isSystemUser = true;
      group = "agent-spawner";
      description = "Agent spawner daemon";
    };
    users.groups.agent-spawner = {};

    # Systemd service with strict sandboxing
    systemd.services.agent-spawner = {
      description = "Secure Agent Spawner Daemon";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "notify";
        ExecStart = "${spawnerDaemon}/bin/agent-spawner";

        # Run as root but with restricted capabilities
        User = "root";

        # Restrict what root can do
        CapabilityBoundingSet = [
          "CAP_SETUID"
          "CAP_SETGID"
          "CAP_SYS_ADMIN"  # For namespaces
        ];

        # Lock down filesystem
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = cfg.allowedWorkspaces ++ [
          "/run/agent-spawner"
          "/var/log/agent-spawner"
        ];

        # Socket activation
        RuntimeDirectory = "agent-spawner";
      };
    };

    # Socket for communication
    systemd.sockets.agent-spawner = {
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = "/run/agent-spawner/spawner.sock";
        SocketMode = "0660";
        SocketUser = "root";
        SocketGroup = "agent-users";  # MCP server user must be in this group
      };
    };
  };
}
```

**Spawner Daemon (restricted API):**

```python
# modules/agent-spawner/src/daemon.py
"""
Privileged spawner daemon with minimal, validated API.
"""

import asyncio
import json
import os
import re
import subprocess
import time
from pathlib import Path

# Configuration (from systemd environment)
MAX_WORKERS = int(os.environ.get("MAX_WORKERS", 10))
ALLOWED_WORKSPACES = os.environ.get("ALLOWED_WORKSPACES", "/mnt/agents").split(":")
SPAWN_COOLDOWN = int(os.environ.get("SPAWN_COOLDOWN", 5))
SOCKET_PATH = "/run/agent-spawner/spawner.sock"

# State
workers: dict[str, dict] = {}
last_spawn_time = 0


def validate_task_id(task_id: str) -> bool:
    """Strict validation: lowercase alphanumeric and hyphens only, 1-64 chars."""
    return bool(re.match(r'^[a-z0-9][a-z0-9-]{0,62}[a-z0-9]?$', task_id))


def validate_workspace(workspace: str) -> bool:
    """Ensure workspace is under allowed directories."""
    workspace_path = Path(workspace).resolve()
    return any(
        workspace_path.is_relative_to(Path(allowed).resolve())
        for allowed in ALLOWED_WORKSPACES
    )


def check_no_symlinks(path: str) -> bool:
    """Verify path contains no symlinks (prevent escape)."""
    current = Path(path)
    while current != current.parent:
        if current.is_symlink():
            return False
        current = current.parent
    return True


async def handle_spawn(request: dict) -> dict:
    """Handle spawn request with full validation."""
    global last_spawn_time

    task_id = request.get("task_id", "")
    workspace = request.get("workspace", "")

    # Validation
    if not validate_task_id(task_id):
        return {"error": f"Invalid task_id: must match [a-z0-9-]{{1,64}}"}

    if not validate_workspace(workspace):
        return {"error": f"Workspace not in allowed directories: {ALLOWED_WORKSPACES}"}

    if task_id in workers:
        return {"error": f"Worker {task_id} already exists"}

    if len(workers) >= MAX_WORKERS:
        return {"error": f"Maximum workers ({MAX_WORKERS}) reached"}

    # Rate limiting
    now = time.time()
    if now - last_spawn_time < SPAWN_COOLDOWN:
        return {"error": f"Spawn cooldown: wait {SPAWN_COOLDOWN}s between spawns"}
    last_spawn_time = now

    # Create workspace with proper permissions
    workspace_path = Path(workspace) / task_id
    workspace_path.mkdir(mode=0o750, parents=True, exist_ok=True)

    # Verify no symlink attacks
    if not check_no_symlinks(str(workspace_path)):
        return {"error": "Symlinks detected in workspace path"}

    # Generate auth token for this worker
    auth_token = os.urandom(32).hex()

    # Spawn via systemd (the secure path)
    result = subprocess.run([
        "systemctl", "start", f"sandboxed-agent@{task_id}"
    ], capture_output=True, text=True)

    if result.returncode != 0:
        return {"error": f"Failed to spawn: {result.stderr}"}

    workers[task_id] = {
        "workspace": str(workspace_path),
        "auth_token": auth_token,
        "started_at": now
    }

    return {
        "task_id": task_id,
        "workspace": str(workspace_path),
        "auth_token": auth_token,
        "status": "spawned"
    }


async def handle_terminate(request: dict) -> dict:
    """Handle terminate request."""
    task_id = request.get("task_id", "")

    if not validate_task_id(task_id):
        return {"error": "Invalid task_id"}

    if task_id not in workers:
        return {"error": f"Worker {task_id} not found"}

    result = subprocess.run([
        "systemctl", "stop", f"sandboxed-agent@{task_id}"
    ], capture_output=True, text=True)

    del workers[task_id]

    return {"task_id": task_id, "status": "terminated"}


async def handle_list(request: dict) -> dict:
    """List active workers."""
    return {
        "workers": [
            {"task_id": k, "workspace": v["workspace"], "started_at": v["started_at"]}
            for k, v in workers.items()
        ]
    }


async def handle_validate_token(request: dict) -> dict:
    """Validate a worker's auth token."""
    task_id = request.get("task_id", "")
    token = request.get("token", "")

    if task_id not in workers:
        return {"valid": False, "error": "Worker not found"}

    expected = workers[task_id].get("auth_token", "")
    valid = token == expected and len(token) == 64

    return {"valid": valid}


HANDLERS = {
    "spawn": handle_spawn,
    "terminate": handle_terminate,
    "list": handle_list,
    "validate_token": handle_validate_token,
}


async def handle_connection(reader, writer):
    """Handle a single client connection."""
    try:
        data = await reader.read(4096)
        request = json.loads(data.decode())

        action = request.get("action", "")
        handler = HANDLERS.get(action)

        if handler:
            response = await handler(request)
        else:
            response = {"error": f"Unknown action: {action}"}

        writer.write(json.dumps(response).encode())
        await writer.drain()
    except Exception as e:
        writer.write(json.dumps({"error": str(e)}).encode())
        await writer.drain()
    finally:
        writer.close()


async def main():
    # Remove existing socket
    Path(SOCKET_PATH).unlink(missing_ok=True)

    server = await asyncio.start_unix_server(handle_connection, SOCKET_PATH)
    os.chmod(SOCKET_PATH, 0o660)

    print(f"Agent spawner listening on {SOCKET_PATH}")

    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
```

### 0.2 Tests for Phase 0

```python
# modules/agent-spawner/tests/test_validation.py
import pytest
from daemon import validate_task_id, validate_workspace

class TestTaskIdValidation:
    def test_valid_simple(self):
        assert validate_task_id("agent1") == True

    def test_valid_with_hyphens(self):
        assert validate_task_id("my-agent-123") == True

    def test_invalid_uppercase(self):
        assert validate_task_id("Agent1") == False

    def test_invalid_path_traversal(self):
        assert validate_task_id("../etc/passwd") == False

    def test_invalid_semicolon(self):
        assert validate_task_id("agent;rm -rf /") == False

    def test_invalid_too_long(self):
        assert validate_task_id("a" * 65) == False

    def test_invalid_empty(self):
        assert validate_task_id("") == False


class TestWorkspaceValidation:
    def test_valid_workspace(self):
        assert validate_workspace("/mnt/agents/test") == True

    def test_invalid_outside_allowed(self):
        assert validate_workspace("/etc/passwd") == False

    def test_invalid_traversal(self):
        assert validate_workspace("/mnt/agents/../etc") == False
```

```bash
# Test script: test-phase0.sh
#!/usr/bin/env bash
set -euo pipefail

echo "=== Phase 0 Tests ==="

echo "1. Testing spawner daemon starts..."
systemctl start agent-spawner
sleep 2
systemctl is-active agent-spawner

echo "2. Testing input validation..."
# Should fail: invalid task_id
RESULT=$(echo '{"action":"spawn","task_id":"../etc","workspace":"/mnt/agents"}' | socat - UNIX-CONNECT:/run/agent-spawner/spawner.sock)
echo "$RESULT" | grep -q "error" && echo "✓ Invalid task_id rejected"

# Should fail: workspace outside allowed
RESULT=$(echo '{"action":"spawn","task_id":"test1","workspace":"/etc"}' | socat - UNIX-CONNECT:/run/agent-spawner/spawner.sock)
echo "$RESULT" | grep -q "error" && echo "✓ Invalid workspace rejected"

echo "3. Testing valid spawn..."
RESULT=$(echo '{"action":"spawn","task_id":"test-agent","workspace":"/mnt/agents"}' | socat - UNIX-CONNECT:/run/agent-spawner/spawner.sock)
echo "$RESULT" | grep -q "spawned" && echo "✓ Valid spawn succeeded"

echo "4. Testing rate limiting..."
RESULT=$(echo '{"action":"spawn","task_id":"test-agent-2","workspace":"/mnt/agents"}' | socat - UNIX-CONNECT:/run/agent-spawner/spawner.sock)
echo "$RESULT" | grep -q "cooldown" && echo "✓ Rate limiting works"

echo "5. Testing terminate..."
RESULT=$(echo '{"action":"terminate","task_id":"test-agent"}' | socat - UNIX-CONNECT:/run/agent-spawner/spawner.sock)
echo "$RESULT" | grep -q "terminated" && echo "✓ Terminate works"

echo "=== Phase 0 PASSED ==="
```

### Phase 0 Deliverables

| Deliverable | File | Test |
|-------------|------|------|
| Spawner daemon | `modules/agent-spawner/src/daemon.py` | `test-phase0.sh` |
| NixOS module | `modules/agent-spawner/default.nix` | `nixos-rebuild` |
| Input validation | Built into daemon | `test_validation.py` |
| Rate limiting | Built into daemon | `test-phase0.sh` step 4 |
| Auth token generation | Built into daemon | Manual |

**Phase 0 is complete when**: Spawner daemon runs, validates all inputs, generates tokens, and can spawn/terminate workers via systemd.

---

## Phase 1: Network Isolation (Builds on Phase 0)

**Goal**: Workers cannot bypass proxy. Network is enforced at OS level, not just env vars.

### 1.1 Network Namespace with Proxy-Only Egress

```nix
# modules/agent-spawner/netns.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.services.agent-spawner;

  # Script to create network namespace for an agent
  createNetns = pkgs.writeShellScriptBin "create-agent-netns" ''
    set -euo pipefail

    TASK_ID="$1"
    PROXY_IP="${cfg.proxyAddress}"
    PROXY_PORT="${toString cfg.proxyPort}"

    NETNS="agent-$TASK_ID"
    VETH_HOST="veth-$TASK_ID"
    VETH_NS="veth-ns-$TASK_ID"

    # Clean up if exists
    ip netns del "$NETNS" 2>/dev/null || true
    ip link del "$VETH_HOST" 2>/dev/null || true

    # Create namespace
    ip netns add "$NETNS"

    # Create veth pair
    ip link add "$VETH_HOST" type veth peer name "$VETH_NS"
    ip link set "$VETH_NS" netns "$NETNS"

    # Configure host side (acts as gateway)
    ip addr add 10.200.0.1/30 dev "$VETH_HOST"
    ip link set "$VETH_HOST" up

    # Configure namespace side
    ip netns exec "$NETNS" ip addr add 10.200.0.2/30 dev "$VETH_NS"
    ip netns exec "$NETNS" ip link set lo up
    ip netns exec "$NETNS" ip link set "$VETH_NS" up
    ip netns exec "$NETNS" ip route add default via 10.200.0.1

    # iptables: Only allow traffic to proxy
    ip netns exec "$NETNS" iptables -P OUTPUT DROP
    ip netns exec "$NETNS" iptables -P INPUT DROP
    ip netns exec "$NETNS" iptables -P FORWARD DROP

    # Allow loopback
    ip netns exec "$NETNS" iptables -A OUTPUT -o lo -j ACCEPT
    ip netns exec "$NETNS" iptables -A INPUT -i lo -j ACCEPT

    # Allow established connections
    ip netns exec "$NETNS" iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    ip netns exec "$NETNS" iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

    # Allow ONLY proxy (via host gateway NAT)
    ip netns exec "$NETNS" iptables -A OUTPUT -d 10.200.0.1 -p tcp --dport "$PROXY_PORT" -j ACCEPT

    # Host-side NAT to proxy
    iptables -t nat -A PREROUTING -i "$VETH_HOST" -p tcp --dport "$PROXY_PORT" -j DNAT --to-destination "$PROXY_IP:$PROXY_PORT"
    iptables -t nat -A POSTROUTING -o "$VETH_HOST" -j MASQUERADE
    iptables -A FORWARD -i "$VETH_HOST" -o "$VETH_HOST" -j ACCEPT

    echo "$NETNS"
  '';

  deleteNetns = pkgs.writeShellScriptBin "delete-agent-netns" ''
    TASK_ID="$1"
    NETNS="agent-$TASK_ID"
    VETH_HOST="veth-$TASK_ID"

    ip netns del "$NETNS" 2>/dev/null || true
    ip link del "$VETH_HOST" 2>/dev/null || true

    # Clean up NAT rules (by comment)
    iptables -t nat -D PREROUTING -i "$VETH_HOST" -j DNAT 2>/dev/null || true
  '';

in {
  options.services.agent-spawner = {
    proxyAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
    };
    proxyPort = lib.mkOption {
      type = lib.types.port;
      default = 3128;
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ createNetns deleteNetns ];

    # Enable IP forwarding for NAT
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
  };
}
```

### 1.2 Updated Systemd Template with Network Namespace

```nix
# modules/agent-spawner/systemd-template.nix
{ config, lib, pkgs, ... }:

{
  systemd.services."sandboxed-agent@" = {
    description = "Sandboxed Agent %i";
    after = [ "network.target" "agent-spawner.service" ];
    requires = [ "agent-spawner.service" ];

    serviceConfig = {
      Type = "simple";

      # Run in network namespace (created by spawner)
      NetworkNamespacePath = "/run/netns/agent-%i";

      ExecStartPre = "${pkgs.writeShellScript "agent-setup" ''
        # Verify network namespace exists
        if [ ! -e /run/netns/agent-%i ]; then
          echo "Network namespace not found for %i"
          exit 1
        fi
      ''}";

      ExecStart = "${pkgs.writeShellScript "run-agent" ''
        exec ${pkgs.bubblewrap}/bin/bwrap \
          --unshare-user \
          --unshare-pid \
          --unshare-ipc \
          --unshare-uts \
          --unshare-cgroup \
          --die-with-parent \
          --new-session \
          \
          --tmpfs / \
          --dev /dev \
          --proc /proc \
          --tmpfs /tmp \
          \
          --ro-bind /nix/store /nix/store \
          --ro-bind /etc/ssl/certs /etc/ssl/certs \
          --ro-bind /etc/resolv.conf /etc/resolv.conf \
          \
          --bind /mnt/agents/%i /workspace \
          \
          --setenv HOME /workspace \
          --setenv HTTP_PROXY "http://10.200.0.1:3128" \
          --setenv HTTPS_PROXY "http://10.200.0.1:3128" \
          --setenv AGENT_ID "%i" \
          \
          --chdir /workspace \
          \
          ${pkgs.opencode}/bin/opencode
      ''}";

      ExecStopPost = "${pkgs.writeShellScript "agent-cleanup" ''
        # Clean up network namespace
        delete-agent-netns %i || true
      ''}";

      # Resource limits
      MemoryMax = "4G";
      CPUQuota = "200%";
      TasksMax = 50;

      # Security
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;

      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "agent-%i";
    };
  };
}
```

### 1.3 Tests for Phase 1

```bash
# test-phase1.sh
#!/usr/bin/env bash
set -euo pipefail

echo "=== Phase 1 Tests: Network Isolation ==="

# Spawn a test agent
echo '{"action":"spawn","task_id":"net-test","workspace":"/mnt/agents"}' | \
  socat - UNIX-CONNECT:/run/agent-spawner/spawner.sock

sleep 3

echo "1. Testing network namespace exists..."
ip netns list | grep -q "agent-net-test" && echo "✓ Network namespace created"

echo "2. Testing agent cannot reach internet directly..."
# This should fail (timeout)
if ip netns exec agent-net-test curl --connect-timeout 3 https://example.com 2>/dev/null; then
  echo "✗ FAIL: Agent can reach internet directly!"
  exit 1
else
  echo "✓ Direct internet access blocked"
fi

echo "3. Testing agent CAN reach proxy..."
if ip netns exec agent-net-test curl --connect-timeout 3 -x http://10.200.0.1:3128 https://example.com 2>/dev/null; then
  echo "✓ Proxy access works"
else
  echo "✗ FAIL: Cannot reach proxy!"
  exit 1
fi

echo "4. Testing DNS exfiltration blocked..."
# Agent should not be able to resolve arbitrary domains without proxy
if ip netns exec agent-net-test nslookup attacker.com 8.8.8.8 2>/dev/null; then
  echo "✗ FAIL: Direct DNS works!"
  exit 1
else
  echo "✓ Direct DNS blocked"
fi

# Cleanup
echo '{"action":"terminate","task_id":"net-test"}' | \
  socat - UNIX-CONNECT:/run/agent-spawner/spawner.sock

echo "=== Phase 1 PASSED ==="
```

### Phase 1 Deliverables

| Deliverable | File | Test |
|-------------|------|------|
| Network namespace creation | `modules/agent-spawner/netns.nix` | `test-phase1.sh` |
| Updated systemd template | `modules/agent-spawner/systemd-template.nix` | Manual |
| NAT to proxy | Built into netns script | step 3 |
| Direct internet blocked | iptables rules | step 2 |

**Phase 1 is complete when**: Workers can ONLY reach the internet via proxy. Direct connections fail.

---

## Phase 2: Proxy Domain Filtering (Builds on Phase 1)

**Goal**: Proxy only allows whitelisted domains.

### 2.1 Squid with Dynamic ACL

```nix
# modules/agent-proxy/default.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.services.agent-proxy;

  squidConfig = pkgs.writeText "squid.conf" ''
    # Ports
    http_port 3128

    # ACLs
    acl localnet src 10.200.0.0/16  # Agent network namespaces
    acl SSL_ports port 443
    acl Safe_ports port 80 443

    # Dynamic domain allowlist (reloaded on SIGHUP)
    acl allowed_domains dstdomain "/var/lib/agent-proxy/allowed-domains.txt"

    # Security
    http_access deny !Safe_ports
    http_access deny CONNECT !SSL_ports

    # Allow only whitelisted domains
    http_access allow localnet allowed_domains
    http_access deny all

    # Logging
    access_log daemon:/var/log/squid/access.log squid

    # Strip sensitive headers
    request_header_access Authorization deny all
    request_header_access X-Api-Key deny all

    # Prevent secrets in URLs from being logged
    strip_query_terms on
  '';

  # Script to update allowed domains
  updateDomains = pkgs.writeShellScriptBin "update-agent-domains" ''
    DOMAINS_FILE="/var/lib/agent-proxy/allowed-domains.txt"

    cat > "$DOMAINS_FILE" << 'EOF'
    # Default allowed domains
    .anthropic.com
    .openai.com
    api.github.com
    EOF

    # Reload squid
    systemctl reload squid || true
  '';

in {
  options.services.agent-proxy = {
    enable = lib.mkEnableOption "Agent egress proxy with domain filtering";

    allowedDomains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ".anthropic.com" ".openai.com" ];
      description = "Domains agents are allowed to access";
    };
  };

  config = lib.mkIf cfg.enable {
    services.squid = {
      enable = true;
      configText = squidConfig;
    };

    # Create domains file from config
    systemd.tmpfiles.rules = [
      "d /var/lib/agent-proxy 0750 squid squid -"
    ];

    system.activationScripts.agentProxyDomains = ''
      mkdir -p /var/lib/agent-proxy
      cat > /var/lib/agent-proxy/allowed-domains.txt << 'EOF'
      ${lib.concatStringsSep "\n" cfg.allowedDomains}
      EOF
      chown squid:squid /var/lib/agent-proxy/allowed-domains.txt
    '';
  };
}
```

### 2.2 Tests for Phase 2

```bash
# test-phase2.sh
#!/usr/bin/env bash
set -euo pipefail

echo "=== Phase 2 Tests: Domain Filtering ==="

# Spawn test agent
echo '{"action":"spawn","task_id":"proxy-test","workspace":"/mnt/agents"}' | \
  socat - UNIX-CONNECT:/run/agent-spawner/spawner.sock

sleep 3

echo "1. Testing allowed domain (anthropic.com)..."
RESULT=$(ip netns exec agent-proxy-test \
  curl -s -o /dev/null -w "%{http_code}" \
  -x http://10.200.0.1:3128 \
  https://api.anthropic.com/v1/messages 2>/dev/null || echo "000")

if [[ "$RESULT" == "401" || "$RESULT" == "200" ]]; then
  echo "✓ Allowed domain accessible (got $RESULT)"
else
  echo "✗ FAIL: Allowed domain blocked (got $RESULT)"
  exit 1
fi

echo "2. Testing blocked domain (example.com)..."
RESULT=$(ip netns exec agent-proxy-test \
  curl -s -o /dev/null -w "%{http_code}" \
  -x http://10.200.0.1:3128 \
  https://example.com 2>/dev/null || echo "000")

if [[ "$RESULT" == "403" || "$RESULT" == "000" ]]; then
  echo "✓ Blocked domain rejected (got $RESULT)"
else
  echo "✗ FAIL: Blocked domain accessible (got $RESULT)"
  exit 1
fi

echo "3. Testing blocked domain (attacker.com)..."
RESULT=$(ip netns exec agent-proxy-test \
  curl -s -o /dev/null -w "%{http_code}" \
  -x http://10.200.0.1:3128 \
  https://attacker.com 2>/dev/null || echo "000")

if [[ "$RESULT" == "403" || "$RESULT" == "000" ]]; then
  echo "✓ Attacker domain rejected"
else
  echo "✗ FAIL: Attacker domain accessible!"
  exit 1
fi

# Cleanup
echo '{"action":"terminate","task_id":"proxy-test"}' | \
  socat - UNIX-CONNECT:/run/agent-spawner/spawner.sock

echo "=== Phase 2 PASSED ==="
```

### Phase 2 Deliverables

| Deliverable | File | Test |
|-------------|------|------|
| Squid with domain ACL | `modules/agent-proxy/default.nix` | `test-phase2.sh` |
| Header stripping | Built into squid.conf | Manual |
| Dynamic domain updates | `update-agent-domains` script | Manual |

**Phase 2 is complete when**: Proxy blocks all domains except explicitly allowed ones.

---

## Phase 3: MCP Server Integration (Builds on Phase 0-2)

**Goal**: Safe MCP server that uses the spawner daemon.

### 3.1 Unprivileged MCP Server

```python
# mcp_servers/a2a_workers/server.py
"""
MCP Server - communicates with spawner daemon via Unix socket.
Runs unprivileged - cannot spawn workers directly.
"""

from mcp.server import Server
from mcp.types import Tool, TextContent
import asyncio
import json
import httpx

app = Server("a2a-workers")

SPAWNER_SOCKET = "/run/agent-spawner/spawner.sock"


async def call_spawner(action: str, **kwargs) -> dict:
    """Call the privileged spawner daemon."""
    request = {"action": action, **kwargs}

    reader, writer = await asyncio.open_unix_connection(SPAWNER_SOCKET)
    writer.write(json.dumps(request).encode())
    await writer.drain()

    response = await reader.read(4096)
    writer.close()
    await writer.wait_closed()

    return json.loads(response.decode())


@app.tool()
async def spawn_worker(task_id: str, workspace: str = "/mnt/agents") -> str:
    """Spawn a sandboxed worker via the spawner daemon."""
    result = await call_spawner("spawn", task_id=task_id, workspace=workspace)

    if "error" in result:
        return f"Error: {result['error']}"

    return f"Worker spawned: {result['task_id']}\nWorkspace: {result['workspace']}"


@app.tool()
async def terminate_worker(task_id: str) -> str:
    """Terminate a worker via the spawner daemon."""
    result = await call_spawner("terminate", task_id=task_id)

    if "error" in result:
        return f"Error: {result['error']}"

    return f"Worker {task_id} terminated"


@app.tool()
async def list_workers() -> str:
    """List active workers."""
    result = await call_spawner("list")

    if "error" in result:
        return f"Error: {result['error']}"

    if not result.get("workers"):
        return "No active workers"

    lines = ["Active workers:"]
    for w in result["workers"]:
        lines.append(f"  - {w['task_id']}: {w['workspace']}")

    return "\n".join(lines)


# ... (other tools from previous plan, but all using call_spawner)


if __name__ == "__main__":
    import mcp.server.stdio
    mcp.server.stdio.run(app)
```

### 3.2 NixOS Module for MCP Server

```nix
# modules/mcp-a2a-workers/default.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.services.mcp-a2a-workers;

  mcpServer = pkgs.python3Packages.buildPythonApplication {
    pname = "mcp-a2a-workers";
    version = "0.1.0";
    src = ./src;
    propagatedBuildInputs = with pkgs.python3Packages; [ mcp httpx ];
  };

in {
  options.services.mcp-a2a-workers = {
    enable = lib.mkEnableOption "MCP server for A2A worker management";
  };

  config = lib.mkIf cfg.enable {
    # MCP server user - unprivileged but in agent-users group
    users.users.mcp-server = {
      isSystemUser = true;
      group = "mcp-server";
      extraGroups = [ "agent-users" ];  # Access to spawner socket
    };
    users.groups.mcp-server = {};

    environment.systemPackages = [ mcpServer ];

    # Ensure agent-users group exists (for socket access)
    users.groups.agent-users = {};
  };
}
```

### Phase 3 Deliverables

| Deliverable | File | Test |
|-------------|------|------|
| Unprivileged MCP server | `mcp_servers/a2a_workers/server.py` | Integration test |
| Socket-based communication | Built into server | `test-phase0.sh` |
| NixOS module | `modules/mcp-a2a-workers/default.nix` | `nixos-rebuild` |

**Phase 3 is complete when**: MCP server can spawn workers but has no direct system access.

---

## Phase 4: A2A Worker Endpoints (Builds on Phase 0-3)

**Goal**: Workers expose A2A endpoints for bidirectional communication.

### 4.1 Worker A2A Sidecar

```python
# worker/a2a_server.py
"""
A2A server running inside the sandbox alongside opencode.
Exposes endpoints for captain to observe and control.
"""

from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import StreamingResponse
from sse_starlette.sse import EventSourceResponse
import asyncio
import subprocess
import os
import json

app = FastAPI()

# Auth token injected by spawner
AUTH_TOKEN = os.environ.get("AUTH_TOKEN", "")
AGENT_ID = os.environ.get("AGENT_ID", "unknown")

# Active task tracking
current_task = None
task_output = []


def verify_auth(request: Request):
    """Verify bearer token matches spawner-provided token."""
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        raise HTTPException(401, "Missing bearer token")

    token = auth[7:]
    if token != AUTH_TOKEN:
        raise HTTPException(403, "Invalid token")


@app.get("/.well-known/agent.json")
async def agent_card():
    """A2A agent card - no auth required for discovery."""
    return {
        "name": f"opencode-worker-{AGENT_ID}",
        "url": f"http://localhost:8080",
        "version": "1.0.0",
        "capabilities": {"streaming": True},
        "skills": [
            {"id": "code", "name": "Code Generation"},
            {"id": "review", "name": "Code Review"}
        ],
        "authentication": {"schemes": ["bearer"]}
    }


@app.post("/tasks/send")
async def send_task(request: Request):
    """Start a new task - streams output via SSE."""
    verify_auth(request)

    global current_task, task_output

    body = await request.json()
    task_id = body.get("id", f"task-{AGENT_ID}")
    message = body["message"]["parts"][0]["text"]

    current_task = task_id
    task_output = []

    async def generate():
        yield {"event": "task.status", "data": json.dumps({"id": task_id, "status": "running"})}

        # Run opencode with the task
        proc = await asyncio.create_subprocess_exec(
            "opencode", "--non-interactive",
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT
        )

        proc.stdin.write(message.encode())
        await proc.stdin.drain()
        proc.stdin.close()

        # Stream output line by line
        async for line in proc.stdout:
            text = line.decode().strip()
            task_output.append(text)
            yield {
                "event": "task.message",
                "data": json.dumps({"role": "assistant", "parts": [{"text": text}]})
            }

        await proc.wait()

        # Collect artifacts
        artifacts = []
        for f in os.listdir("/workspace"):
            if os.path.isfile(f"/workspace/{f}"):
                artifacts.append({"name": f})

        status = "completed" if proc.returncode == 0 else "failed"
        yield {
            "event": "task.status",
            "data": json.dumps({"id": task_id, "status": status, "artifacts": artifacts})
        }

        global current_task
        current_task = None

    return EventSourceResponse(generate())


@app.post("/tasks/{task_id}/messages")
async def add_message(task_id: str, request: Request):
    """Add a message to an active task (for ask/resteer)."""
    verify_auth(request)

    if current_task != task_id:
        raise HTTPException(404, "Task not found or not active")

    body = await request.json()
    message = body["message"]["parts"][0]["text"]

    # TODO: Inject message into running opencode process
    # For now, just acknowledge
    return {"acknowledged": True, "message": message}


@app.post("/tasks/{task_id}/cancel")
async def cancel_task(task_id: str, request: Request):
    """Cancel the current task."""
    verify_auth(request)

    if current_task != task_id:
        raise HTTPException(404, "Task not found or not active")

    # Kill opencode process
    subprocess.run(["pkill", "-f", "opencode"], check=False)

    global current_task
    current_task = None

    return {"cancelled": True}


@app.get("/stream")
async def stream_logs(request: Request):
    """Stream real-time logs."""
    verify_auth(request)

    async def generate():
        # Stream from task output buffer
        seen = 0
        while True:
            if len(task_output) > seen:
                for line in task_output[seen:]:
                    yield f"data: {line}\n\n"
                seen = len(task_output)
            await asyncio.sleep(0.1)

    return StreamingResponse(generate(), media_type="text/event-stream")


@app.get("/files")
async def list_files(request: Request, path: str = "/workspace"):
    """List files in workspace."""
    verify_auth(request)

    files = []
    for f in os.listdir(path):
        filepath = os.path.join(path, f)
        stat = os.stat(filepath)
        files.append({
            "name": f,
            "size": stat.st_size,
            "is_dir": os.path.isdir(filepath)
        })

    return {"files": files}


@app.get("/files/content")
async def read_file(request: Request, path: str):
    """Read file contents."""
    verify_auth(request)

    # Validate path is under workspace
    full_path = os.path.abspath(os.path.join("/workspace", path))
    if not full_path.startswith("/workspace/"):
        raise HTTPException(403, "Path outside workspace")

    with open(full_path, "r") as f:
        return f.read()


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
```

### Phase 4 Deliverables

| Deliverable | File | Test |
|-------------|------|------|
| A2A worker sidecar | `worker/a2a_server.py` | Integration test |
| Auth token validation | Built into sidecar | Test with invalid token |
| Streaming output | SSE endpoints | Manual |
| File inspection | `/files` endpoints | Manual |

**Phase 4 is complete when**: Captain can observe worker output, ask questions, and control workers via A2A.

---

## Phase Summary

| Phase | Goal | Security Fixes | Testable Independently |
|-------|------|----------------|------------------------|
| 0 | Foundation | Privilege separation, input validation, rate limiting | ✅ |
| 1 | Network | Network namespace, proxy enforcement | ✅ |
| 2 | Domains | Allowlist filtering | ✅ |
| 3 | MCP | Unprivileged MCP server | ✅ |
| 4 | A2A | Worker endpoints with auth | ✅ |

---

## Test Matrix

| Test | Phase | Command |
|------|-------|---------|
| Input validation | 0 | `pytest test_validation.py` |
| Spawner integration | 0 | `./test-phase0.sh` |
| Network isolation | 1 | `./test-phase1.sh` |
| Domain filtering | 2 | `./test-phase2.sh` |
| MCP → Spawner | 3 | `./test-phase3.sh` |
| End-to-end | 4 | `./test-e2e.sh` |

---

## Rollout Plan

1. **Deploy Phase 0**: Spawner daemon on single node → Test
2. **Deploy Phase 1**: Network namespaces → Test isolation
3. **Deploy Phase 2**: Proxy filtering → Test domain blocks
4. **Deploy Phase 3**: MCP server → Test captain can spawn
5. **Deploy Phase 4**: A2A sidecar → Full integration test

Each phase is a working system. No phase leaves security holes that the next phase must fix.

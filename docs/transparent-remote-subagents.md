# Transparent Remote Subagents for OpenCode

## Executive Summary

Extend OpenCode's native subagent system so that subagents transparently execute in **sandboxed remote processes** while maintaining the exact same UX as local subagents.

**Captain (OpenCode) sees**: Normal `@subagent` invocation, streaming responses
**What actually happens**: Sandboxed process with network/filesystem isolation

---

## Problem Statement

OpenCode has a built-in subagent system:
- Subagents have isolated conversation contexts
- Can restrict tools per subagent
- Invoked via `@subagent-name` or automatic delegation

**But**: Subagents run in the **same process** as the captain. No OS-level isolation.

For untrusted tasks (code from internet, user-provided repos, etc.), we need:
- Filesystem isolation (only workspace accessible)
- Network isolation (proxy-only egress)
- Resource limits (CPU, memory, processes)
- Audit logging

---

## Solution: Transparent Remote Subagent Provider

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     Captain (OpenCode)                                   │
│                                                                          │
│   @code-reviewer "review src/api for security issues"                   │
│         │                                                                │
│         │ (same syntax as local subagent)                               │
│         ▼                                                                │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │              RemoteSubagentProvider                              │   │
│   │                                                                  │   │
│   │  Intercepts subagent spawn, creates sandbox instead of local    │   │
│   │  Proxies all I/O transparently                                  │   │
│   │  Captain doesn't know the difference                            │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│         │                                                                │
└─────────┼────────────────────────────────────────────────────────────────┘
          │
          │ Unix Socket: /run/agent-spawner/spawner.sock
          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Spawner Daemon (privileged)                           │
│                                                                          │
│  - Validates input (task_id, workspace)                                 │
│  - Rate limits (max workers, cooldown)                                  │
│  - Creates network namespace                                            │
│  - Spawns sandboxed worker                                              │
│  - Returns I/O socket path                                              │
└─────────────────────────────────────────────────────────────────────────┘
          │
          │ Creates
          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Sandboxed Worker                                      │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  Network Namespace (agent-{task_id})                              │  │
│  │   - iptables: ONLY proxy reachable                                │  │
│  │   - No direct internet                                            │  │
│  │                                                                    │  │
│  │  ┌─────────────────────────────────────────────────────────────┐ │  │
│  │  │  Bubblewrap Sandbox                                          │ │  │
│  │  │   - Filesystem: only /mnt/agents/{task_id} writable         │ │  │
│  │  │   - /nix/store: minimal closure, read-only                  │ │  │
│  │  │   - No access to /home, /root, /etc                         │ │  │
│  │  │                                                              │ │  │
│  │  │  ┌─────────────────────────────────────────────────────┐   │ │  │
│  │  │  │  OpenCode Instance                                   │   │ │  │
│  │  │  │   - Loaded with subagent config                     │   │ │  │
│  │  │  │   - Restricted tools                                │   │ │  │
│  │  │  │   - I/O via /run/agents/{task_id}/io.sock          │   │ │  │
│  │  │  └─────────────────────────────────────────────────────┘   │ │  │
│  │  └─────────────────────────────────────────────────────────────┘ │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Component Details

### 1. RemoteSubagentProvider (TypeScript)

Hooks into OpenCode's subagent system. When a subagent is invoked:
1. Calls spawner daemon to create sandbox
2. Connects to worker's I/O socket
3. Returns interface identical to local subagent
4. Captain sees no difference

```typescript
// remote-subagent/provider.ts

import { SubagentProvider, SubagentSession, AgentConfig } from "opencode";
import { connect, Socket } from "net";

interface RemoteSubagentConfig {
  spawnerSocket: string;        // /run/agent-spawner/spawner.sock
  workspaceBase: string;        // /mnt/agents
  proxy: string;                // http://127.0.0.1:3128
  remoteAgents?: string[];      // Which agents run remotely (default: all)
  localAgents?: string[];       // Which agents stay local
}

export class RemoteSubagentProvider implements SubagentProvider {
  private config: RemoteSubagentConfig;
  private activeSessions: Map<string, RemoteSession> = new Map();

  constructor(config: RemoteSubagentConfig) {
    this.config = config;
  }

  /**
   * Determine if this agent should run remotely or locally
   */
  private shouldRunRemotely(agentName: string): boolean {
    if (this.config.localAgents?.includes(agentName)) {
      return false;
    }
    if (this.config.remoteAgents) {
      return this.config.remoteAgents.includes(agentName);
    }
    return true; // Default: all remote
  }

  /**
   * Called by OpenCode when @subagent is invoked
   */
  async createSession(
    agentName: string,
    agentConfig: AgentConfig
  ): Promise<SubagentSession> {

    if (!this.shouldRunRemotely(agentName)) {
      // Fall back to default local behavior
      return this.createLocalSession(agentName, agentConfig);
    }

    const sessionId = `${agentName}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    const workspace = `${this.config.workspaceBase}/${sessionId}`;

    // 1. Request sandbox from spawner daemon
    const spawnResult = await this.callSpawner({
      action: "spawn",
      task_id: sessionId,
      workspace: workspace,
      agent_config: {
        name: agentName,
        model: agentConfig.model || "sonnet",
        tools: agentConfig.tools || [],
        systemPrompt: agentConfig.systemPrompt || "",
      }
    });

    if (spawnResult.error) {
      throw new Error(`Failed to spawn sandbox: ${spawnResult.error}`);
    }

    // 2. Connect to worker's I/O socket
    const ioSocketPath = `/run/agents/${sessionId}/io.sock`;
    const session = new RemoteSession(sessionId, ioSocketPath, spawnResult.auth_token);

    // Wait for worker to be ready (socket exists)
    await session.waitForReady(30000); // 30s timeout
    await session.connect();

    this.activeSessions.set(sessionId, session);

    // 3. Return session interface (identical to local subagent)
    return {
      id: sessionId,
      agentName: agentName,

      /**
       * Send message to subagent
       */
      send: async (message: string): Promise<void> => {
        await session.sendMessage({
          role: "user",
          content: message
        });
      },

      /**
       * Stream response from subagent (async generator)
       */
      receive: async function* (): AsyncGenerator<string, void, unknown> {
        for await (const chunk of session.receiveStream()) {
          yield chunk;
        }
      },

      /**
       * End session and cleanup sandbox
       */
      end: async (): Promise<void> => {
        await session.close();
        await this.terminateSession(sessionId);
      },

      /**
       * Check if session is still active
       */
      isActive: (): boolean => {
        return session.isConnected();
      }
    };
  }

  /**
   * Call the privileged spawner daemon
   */
  private callSpawner(request: object): Promise<any> {
    return new Promise((resolve, reject) => {
      const socket = connect(this.config.spawnerSocket);

      socket.on("connect", () => {
        socket.write(JSON.stringify(request));
      });

      socket.on("data", (data) => {
        try {
          resolve(JSON.parse(data.toString()));
        } catch (e) {
          reject(new Error(`Invalid response from spawner: ${data}`));
        }
        socket.end();
      });

      socket.on("error", (err) => {
        reject(new Error(`Spawner connection failed: ${err.message}`));
      });

      socket.setTimeout(10000, () => {
        reject(new Error("Spawner timeout"));
        socket.destroy();
      });
    });
  }

  /**
   * Terminate a sandbox
   */
  private async terminateSession(sessionId: string): Promise<void> {
    await this.callSpawner({
      action: "terminate",
      task_id: sessionId
    });
    this.activeSessions.delete(sessionId);
  }

  /**
   * Cleanup all sessions (called on shutdown)
   */
  async shutdown(): Promise<void> {
    for (const [sessionId, session] of this.activeSessions) {
      await session.close();
      await this.terminateSession(sessionId);
    }
  }
}


/**
 * Handles I/O with a remote sandboxed worker
 */
class RemoteSession {
  private socket: Socket | null = null;
  private connected: boolean = false;
  private buffer: string = "";

  constructor(
    public readonly id: string,
    private socketPath: string,
    private authToken: string
  ) {}

  /**
   * Wait for worker to create the I/O socket
   */
  async waitForReady(timeoutMs: number): Promise<void> {
    const start = Date.now();
    const fs = await import("fs/promises");

    while (Date.now() - start < timeoutMs) {
      try {
        await fs.access(this.socketPath);
        return; // Socket exists
      } catch {
        await new Promise(r => setTimeout(r, 100));
      }
    }

    throw new Error(`Worker socket not ready after ${timeoutMs}ms`);
  }

  /**
   * Connect to worker's I/O socket
   */
  async connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.socket = connect(this.socketPath);

      this.socket.on("connect", () => {
        this.connected = true;
        // Send auth token as first message
        this.socket!.write(JSON.stringify({ auth: this.authToken }) + "\n");
        resolve();
      });

      this.socket.on("error", (err) => {
        this.connected = false;
        reject(err);
      });

      this.socket.on("close", () => {
        this.connected = false;
      });
    });
  }

  /**
   * Send a message to the worker
   */
  async sendMessage(message: { role: string; content: string }): Promise<void> {
    if (!this.socket || !this.connected) {
      throw new Error("Not connected to worker");
    }

    return new Promise((resolve, reject) => {
      const data = JSON.stringify(message) + "\n";
      this.socket!.write(data, (err) => {
        if (err) reject(err);
        else resolve();
      });
    });
  }

  /**
   * Stream responses from the worker
   */
  async *receiveStream(): AsyncGenerator<string, void, unknown> {
    if (!this.socket) {
      throw new Error("Not connected to worker");
    }

    const readline = await import("readline");
    const rl = readline.createInterface({ input: this.socket });

    for await (const line of rl) {
      try {
        const msg = JSON.parse(line);

        if (msg.type === "chunk") {
          yield msg.content;
        } else if (msg.type === "done") {
          break;
        } else if (msg.type === "error") {
          throw new Error(msg.error);
        }
      } catch (e) {
        // Non-JSON line, yield as-is
        yield line;
      }
    }
  }

  isConnected(): boolean {
    return this.connected;
  }

  async close(): Promise<void> {
    if (this.socket) {
      this.socket.end();
      this.socket = null;
      this.connected = false;
    }
  }
}
```

### 2. Worker I/O Server (runs inside sandbox)

```typescript
// agent-worker/io-server.ts

import { createServer, Socket } from "net";
import { spawn, ChildProcess } from "child_process";
import * as readline from "readline";

const IO_SOCKET = process.env.IO_SOCKET || "/run/agent/io.sock";
const AUTH_TOKEN = process.env.AUTH_TOKEN || "";
const AGENT_CONFIG = process.env.AGENT_CONFIG || "{}";

class WorkerIOServer {
  private server: any;
  private opencode: ChildProcess | null = null;
  private authenticated: boolean = false;

  async start(): Promise<void> {
    // Start OpenCode process
    this.opencode = spawn("opencode", ["--non-interactive", "--agent-mode"], {
      stdio: ["pipe", "pipe", "pipe"],
      env: {
        ...process.env,
        OPENCODE_CONFIG: AGENT_CONFIG,
      }
    });

    // Create I/O socket server
    this.server = createServer(this.handleConnection.bind(this));

    // Remove existing socket
    const fs = await import("fs/promises");
    await fs.unlink(IO_SOCKET).catch(() => {});

    this.server.listen(IO_SOCKET);
    await fs.chmod(IO_SOCKET, 0o600);

    console.log(`Worker I/O server listening on ${IO_SOCKET}`);

    // Stream OpenCode stdout to connected client
    this.opencode.stdout?.on("data", (data) => {
      this.broadcastToClients({
        type: "chunk",
        content: data.toString()
      });
    });

    this.opencode.stderr?.on("data", (data) => {
      this.broadcastToClients({
        type: "chunk",
        content: data.toString()
      });
    });

    this.opencode.on("exit", (code) => {
      this.broadcastToClients({
        type: "done",
        exitCode: code
      });
    });
  }

  private clients: Set<Socket> = new Set();

  private handleConnection(socket: Socket): void {
    const rl = readline.createInterface({ input: socket });

    rl.on("line", (line) => {
      try {
        const msg = JSON.parse(line);

        // First message must be auth
        if (!this.authenticated) {
          if (msg.auth === AUTH_TOKEN) {
            this.authenticated = true;
            this.clients.add(socket);
            socket.write(JSON.stringify({ type: "authenticated" }) + "\n");
          } else {
            socket.write(JSON.stringify({ type: "error", error: "Invalid auth token" }) + "\n");
            socket.end();
          }
          return;
        }

        // Forward user messages to OpenCode stdin
        if (msg.role === "user") {
          this.opencode?.stdin?.write(msg.content + "\n");
        }

      } catch (e) {
        // Non-JSON, forward as-is
        this.opencode?.stdin?.write(line + "\n");
      }
    });

    socket.on("close", () => {
      this.clients.delete(socket);
    });
  }

  private broadcastToClients(message: object): void {
    const data = JSON.stringify(message) + "\n";
    for (const client of this.clients) {
      client.write(data);
    }
  }
}

// Start server
const server = new WorkerIOServer();
server.start().catch(console.error);
```

### 3. Spawner Daemon Updates

Add agent config support to the spawner:

```python
# Addition to spawner daemon

async def handle_spawn(request: dict) -> dict:
    task_id = request.get("task_id", "")
    workspace = request.get("workspace", "")
    agent_config = request.get("agent_config", {})

    # ... validation ...

    # Generate auth token
    auth_token = os.urandom(32).hex()

    # Write agent config for worker to read
    config_path = f"{workspace_path}/.agent-config.json"
    with open(config_path, "w") as f:
        json.dump(agent_config, f)
    os.chmod(config_path, 0o600)

    # Create network namespace
    subprocess.run(["create-agent-netns", task_id], check=True)

    # Start systemd service with environment
    env_file = f"/run/agents/{task_id}/env"
    os.makedirs(os.path.dirname(env_file), exist_ok=True)
    with open(env_file, "w") as f:
        f.write(f"AUTH_TOKEN={auth_token}\n")
        f.write(f"AGENT_CONFIG={json.dumps(agent_config)}\n")
        f.write(f"IO_SOCKET=/run/agents/{task_id}/io.sock\n")

    subprocess.run([
        "systemctl", "start", f"sandboxed-agent@{task_id}"
    ], check=True)

    return {
        "task_id": task_id,
        "workspace": str(workspace_path),
        "auth_token": auth_token,
        "io_socket": f"/run/agents/{task_id}/io.sock",
        "status": "spawned"
    }
```

### 4. OpenCode Configuration

```typescript
// opencode.config.ts

import { defineConfig } from "opencode";
import { RemoteSubagentProvider } from "@myorg/remote-subagent";

export default defineConfig({
  // Use remote subagents for sandboxed execution
  subagentProvider: new RemoteSubagentProvider({
    spawnerSocket: "/run/agent-spawner/spawner.sock",
    workspaceBase: "/mnt/agents",
    proxy: "http://127.0.0.1:3128",

    // These agents run remotely (sandboxed)
    remoteAgents: [
      "code-reviewer",
      "test-writer",
      "api-builder",
      "security-auditor",
      "dependency-checker",
    ],

    // These stay local (trusted, need full access)
    localAgents: [
      "plan",
      "explore",
    ],
  }),

  // Rest of config...
});
```

---

## Usage Examples

### Captain Perspective (unchanged from normal subagents)

```
You: Review my API for security issues and write tests

Captain: I'll have the security team review this.

    @security-auditor Please review src/api/ for vulnerabilities

    security-auditor: I've found 3 issues:

    1. SQL Injection in users.py:45
       The query uses string formatting instead of parameterized queries.

    2. Missing CSRF protection in forms.py
       POST endpoints don't validate CSRF tokens.

    3. Hardcoded secret in config.py:12
       API_KEY should be loaded from environment.

    [Session automatically terminates, sandbox destroyed]

    @test-writer Write tests for the issues found above

    test-writer: I'll create security regression tests:

    ```python
    # test_security.py
    def test_sql_injection_prevented():
        ...
    ```

    [Session terminates, sandbox destroyed]

Captain: Security review complete. Found 3 issues and created regression tests.
```

### What Happens Behind the Scenes

```
1. Captain invokes @security-auditor

2. RemoteSubagentProvider intercepts:
   - Calls spawner: spawn("security-auditor-1706123456", ...)
   - Spawner creates network namespace
   - Spawner creates bubblewrap sandbox
   - Spawner starts opencode in sandbox
   - Spawner returns auth_token and io_socket path

3. Provider connects to io_socket
   - Authenticates with token
   - Sends user message

4. Worker (in sandbox) runs opencode
   - Limited to /mnt/agents/security-auditor-1706123456
   - Network only via proxy
   - Streams responses back via socket

5. Provider streams responses to captain
   - Captain sees normal subagent output

6. Session ends
   - Provider calls spawner: terminate("security-auditor-1706123456")
   - Spawner stops systemd service
   - Spawner deletes network namespace
   - Spawner cleans up workspace
```

---

## Security Properties

| Property | How Enforced |
|----------|--------------|
| Filesystem isolation | Bubblewrap: only workspace writable |
| Network isolation | Network namespace + iptables: proxy only |
| Resource limits | systemd: MemoryMax, CPUQuota, TasksMax |
| Auth between captain/worker | Per-session random token |
| Input validation | Spawner validates task_id, workspace |
| Rate limiting | Spawner enforces cooldown, max workers |
| Audit logging | Spawner logs all spawn/terminate |

---

## Files to Implement

```
modules/
├── remote-subagent/
│   ├── provider.ts         # RemoteSubagentProvider
│   ├── session.ts          # RemoteSession (I/O handling)
│   ├── index.ts            # Exports
│   ├── package.json
│   └── default.nix         # NixOS packaging
│
├── agent-worker/
│   ├── io-server.ts        # Worker-side I/O server
│   ├── wrapper.sh          # Starts opencode with config
│   ├── package.json
│   └── default.nix
│
└── agent-spawner/
    ├── daemon.py           # Already defined
    ├── netns.nix           # Already defined
    └── systemd-template.nix # Already defined
```

---

## Integration with Existing Plan

This replaces the MCP server approach with a cleaner integration:

| Old Approach | New Approach |
|--------------|--------------|
| MCP server exposes tools | RemoteSubagentProvider hooks OpenCode |
| Captain calls `spawn_worker` tool | Captain uses `@subagent` (transparent) |
| Manual A2A communication | I/O socket proxying (automatic) |
| Captain manages worker lifecycle | Provider manages automatically |

The spawner daemon, network namespace, and bubblewrap sandbox remain the same.
Only the **interface to captain** changes: from explicit tools to transparent subagents.

---

## Testing

### Unit Tests

```typescript
// remote-subagent/provider.test.ts

describe("RemoteSubagentProvider", () => {
  it("spawns sandbox for remote agent", async () => {
    const provider = new RemoteSubagentProvider({...});
    const session = await provider.createSession("code-reviewer", {...});

    expect(session.id).toMatch(/^code-reviewer-\d+/);
    // Verify spawner was called
    // Verify socket connected
  });

  it("falls back to local for localAgents", async () => {
    const provider = new RemoteSubagentProvider({
      localAgents: ["plan"]
    });
    const session = await provider.createSession("plan", {...});

    // Verify no spawner call
    // Verify local session created
  });

  it("cleans up sandbox on session end", async () => {
    const session = await provider.createSession("test", {...});
    await session.end();

    // Verify terminate called
    // Verify socket closed
  });
});
```

### Integration Tests

```bash
#!/usr/bin/env bash
# test-transparent-subagent.sh

echo "=== Transparent Remote Subagent Tests ==="

# 1. Start spawner daemon
systemctl start agent-spawner

# 2. Run opencode with remote subagent config
cat > /tmp/test-config.ts << 'EOF'
import { RemoteSubagentProvider } from "@myorg/remote-subagent";
export default {
  subagentProvider: new RemoteSubagentProvider({
    spawnerSocket: "/run/agent-spawner/spawner.sock",
    workspaceBase: "/mnt/agents",
  })
};
EOF

# 3. Invoke subagent
echo "@test-agent say hello" | opencode --config /tmp/test-config.ts

# 4. Verify sandbox was created
ls /mnt/agents/ | grep -q "test-agent-" && echo "✓ Workspace created"

# 5. Verify sandbox was cleaned up
sleep 2
ls /mnt/agents/ | grep -q "test-agent-" && echo "✗ Workspace not cleaned" || echo "✓ Workspace cleaned"

echo "=== Tests Complete ==="
```

---

## Migration Path

1. **Phase 1**: Implement RemoteSubagentProvider alongside existing local provider
2. **Phase 2**: Configure specific agents as remote (start with untrusted tasks)
3. **Phase 3**: Default all agents to remote, whitelist trusted ones as local
4. **Phase 4**: Remove local fallback for security-critical deployments

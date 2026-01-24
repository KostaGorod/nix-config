# Mem0 Self-Hosted Setup

Mem0 provides persistent memory capabilities for AI coding agents like OpenCode and Claude Code. This setup uses **self-hosted mode** with local Qdrant vector storage.

## Installation

```bash
sudo nixos-rebuild switch --flake .#rocinante
```

## Configuration

```nix
# User-level tools and wrapper scripts
programs.mem0 = {
  enable = true;
  selfHosted = true;
  userId = "kosta";
};

# Systemd service (SSE transport on port 8050)
services.mem0 = {
  enable = true;
  port = 8050;
  userId = "kosta";
};
```

## Verify Service

```bash
# Check service status
systemctl status mem0

# View logs
journalctl -u mem0 -f

# Test with curl
curl http://localhost:8050/sse

# Test health/info endpoint
curl http://localhost:8050/
```

## OpenCode MCP Integration (SSE)

Add to `~/.config/opencode/opencode.json`:

```json
{
  "mcp": {
    "mem0": {
      "transport": "sse",
      "url": "http://localhost:8050/sse",
      "env": {
        "MEM0_DEFAULT_USER_ID": "kosta"
      }
    }
  }
}
```

## Claude Code MCP Integration (SSE)

```json
{
  "mcpServers": {
    "mem0": {
      "transport": "sse",
      "url": "http://localhost:8050/sse"
    }
  }
}
```

## Alternative: Stdio Mode (on-demand)

If you prefer stdio mode (no persistent service), use the wrapper script:

```json
{
  "mcp": {
    "mem0": {
      "command": "uvx",
      "args": ["mem0-mcp"],
      "env": {
        "MEM0_DEFAULT_USER_ID": "kosta"
      }
    }
  }
}
```

## Using Local Embeddings (Ollama)

For fully local operation without OpenAI, create `~/.config/mem0/config.yaml`:

```yaml
embedder:
  provider: ollama
  config:
    model: nomic-embed-text
    ollama_base_url: http://localhost:11434

llm:
  provider: ollama
  config:
    model: llama3.2
    ollama_base_url: http://localhost:11434

vector_store:
  provider: qdrant
  config:
    path: /var/lib/mem0/qdrant
```

## Data Locations

- **Service data**: `/var/lib/mem0/qdrant`
- **User data**: `~/.local/share/mem0/qdrant`

## Environment Variables

- `MEM0_DEFAULT_USER_ID`: Default user ID (set to "kosta")
- `MEM0_DATA_DIR`: Storage path
- `OPENAI_API_KEY`: Required for embeddings (unless using Ollama)

## Resources

- [Mem0 Self-Hosted Docs](https://docs.mem0.ai/open-source/python-quickstart)
- [Mem0 MCP Integration](https://docs.mem0.ai/platform/features/mcp-integration)
- [OpenCode MCP Servers](https://opencode.ai/docs/mcp-servers/)

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

# Systemd service with VoyageAI embeddings
services.mem0 = {
  enable = true;
  port = 8050;
  userId = "kosta";

  # VoyageAI embeddings (voyage-4-lite)
  embedder = {
    provider = "voyageai";
    model = "voyage-4-lite";
    apiKeyFile = "/run/secrets/voyage-api-key";
  };

  # LLM for memory extraction
  llm = {
    provider = "anthropic";
    model = "claude-sonnet-4-20250514";
    apiKeyFile = "/run/secrets/anthropic-api-key";
  };
};
```

## Setup API Keys

Create the secret files (root-only readable):

```bash
# VoyageAI API key
sudo mkdir -p /run/secrets
echo "pa-YOUR_VOYAGE_API_KEY" | sudo tee /run/secrets/voyage-api-key
sudo chmod 600 /run/secrets/voyage-api-key

# Anthropic API key
echo "sk-ant-YOUR_ANTHROPIC_KEY" | sudo tee /run/secrets/anthropic-api-key
sudo chmod 600 /run/secrets/anthropic-api-key
```

Get your keys from:
- VoyageAI: https://dash.voyageai.com/
- Anthropic: https://console.anthropic.com/

## Verify Service

```bash
# Check service status
systemctl status mem0

# View logs
journalctl -u mem0 -f

# Test SSE endpoint
curl -N http://localhost:8050/sse

# Check port is listening
ss -tlnp | grep 8050
```

## OpenCode MCP Integration (SSE)

Add to `~/.config/opencode/opencode.json`:

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

## Claude Code MCP Integration (SSE)

```bash
claude mcp add mem0 --transport sse --url http://localhost:8050/sse
```

Or manually add to settings:

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

## Embedder Options

| Provider | Model | Notes |
|----------|-------|-------|
| `voyageai` | `voyage-4-lite` | Fast, cost-effective (recommended) |
| `voyageai` | `voyage-4` | Higher quality |
| `voyageai` | `voyage-code-3` | Optimized for code |
| `openai` | `text-embedding-3-small` | OpenAI default |
| `ollama` | `nomic-embed-text` | Fully local |

## LLM Options

| Provider | Model | Notes |
|----------|-------|-------|
| `anthropic` | `claude-sonnet-4-20250514` | Best for memory extraction |
| `openai` | `gpt-4.1-nano-2025-04-14` | Default |
| `ollama` | `llama3.2` | Fully local |

## Data Locations

- **Service data**: `/var/lib/mem0/qdrant`
- **User data**: `~/.local/share/mem0/qdrant`

## Test Memory Sharing

In Claude Code:
```
Store a memory that I prefer NixOS with flakes
```

In OpenCode:
```
What do you know about my OS preferences?
```

Both agents share the same memory store via the service.

## Resources

- [Mem0 Self-Hosted Docs](https://docs.mem0.ai/open-source/python-quickstart)
- [VoyageAI Models](https://docs.voyageai.com/docs/embeddings)
- [Mem0 MCP Integration](https://docs.mem0.ai/platform/features/mcp-integration)

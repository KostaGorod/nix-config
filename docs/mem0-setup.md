# Mem0 Integration Setup

Mem0 provides persistent memory capabilities for AI coding agents like OpenCode and Claude Code.

## Installation

The `mem0` module is enabled in your NixOS configuration. After rebuilding:

```bash
sudo nixos-rebuild switch --flake .#rocinante
```

## OpenCode MCP Integration

Add the following to your OpenCode configuration at `~/.config/opencode/opencode.json`:

### Cloud Mode (Recommended for production)

```json
{
  "mcp": {
    "mem0": {
      "command": "uvx",
      "args": ["mem0-mcp"],
      "env": {
        "MEM0_API_KEY": "<your-api-key-from-app.mem0.ai>",
        "MEM0_DEFAULT_USER_ID": "kosta"
      }
    }
  }
}
```

Get your API key from [app.mem0.ai](https://app.mem0.ai).

### Local Mode (Self-hosted with Qdrant)

For local-only memory storage without cloud:

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

In local mode, mem0 uses Qdrant with on-disk storage at `~/.local/share/mem0`.

## Claude Code MCP Integration

Add to your Claude Code MCP settings (`~/.config/claude-code/settings.json`):

```json
{
  "mcpServers": {
    "mem0": {
      "command": "uvx",
      "args": ["mem0-mcp"],
      "env": {
        "MEM0_API_KEY": "<your-api-key>",
        "MEM0_DEFAULT_USER_ID": "kosta"
      }
    }
  }
}
```

## Python Library Usage

For direct Python usage:

```bash
# Install mem0ai via uv
uv pip install mem0ai

# Or use in a project
uv add mem0ai
```

Example usage:

```python
from mem0 import Memory

m = Memory()

# Add memories
messages = [
    {"role": "user", "content": "I prefer using NixOS for all my systems."},
    {"role": "assistant", "content": "Noted! I'll remember your preference for NixOS."}
]
m.add(messages, user_id="kosta")

# Search memories
results = m.search("operating system preferences", user_id="kosta")
print(results)
```

## Environment Variables

- `MEM0_API_KEY`: API key for mem0 cloud service (optional for local mode)
- `MEM0_DEFAULT_USER_ID`: Default user ID for memory operations
- `MEM0_DATA_DIR`: Local data directory (default: `~/.local/share/mem0`)

## Resources

- [Mem0 Documentation](https://docs.mem0.ai/)
- [Mem0 MCP Integration](https://docs.mem0.ai/platform/features/mcp-integration)
- [OpenCode MCP Servers](https://opencode.ai/docs/mcp-servers/)

# Mem0 Self-Hosted Setup

Mem0 provides persistent memory capabilities for AI coding agents like OpenCode and Claude Code. This setup uses **self-hosted mode** with local Qdrant vector storage.

## Installation

The `mem0` module is enabled in your NixOS configuration with self-hosted mode. After rebuilding:

```bash
sudo nixos-rebuild switch --flake .#rocinante
```

## Configuration

Current settings in `configuration.nix`:

```nix
programs.mem0 = {
  enable = true;
  selfHosted = true;
  userId = "kosta";
};
```

Data is stored locally at `~/.local/share/mem0/qdrant`.

## OpenCode MCP Integration

Add to `~/.config/opencode/opencode.json`:

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

**Note:** Self-hosted mode requires `OPENAI_API_KEY` for embeddings. Set it in your environment or add to the `env` block above.

## Claude Code MCP Integration

Add to your Claude Code MCP settings:

```json
{
  "mcpServers": {
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

## Using Alternative Embedding Models

For fully local operation without OpenAI, configure mem0 to use Ollama or other local models. Create `~/.config/mem0/config.yaml`:

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
    path: ~/.local/share/mem0/qdrant
```

## Python Library Usage

```bash
# Install mem0ai
uv pip install mem0ai
```

```python
from mem0 import Memory

m = Memory()

# Add memories
messages = [
    {"role": "user", "content": "I prefer NixOS with flakes."},
    {"role": "assistant", "content": "Noted! I'll remember your NixOS preference."}
]
m.add(messages, user_id="kosta")

# Search memories
results = m.search("operating system", user_id="kosta")
```

## Environment Variables

- `MEM0_DEFAULT_USER_ID`: Default user ID (set to "kosta")
- `MEM0_DATA_DIR`: Local storage path (`~/.local/share/mem0`)
- `OPENAI_API_KEY`: Required for embeddings (unless using Ollama)

## Resources

- [Mem0 Self-Hosted Docs](https://docs.mem0.ai/open-source/python-quickstart)
- [Mem0 MCP Integration](https://docs.mem0.ai/platform/features/mcp-integration)
- [OpenCode MCP Servers](https://opencode.ai/docs/mcp-servers/)

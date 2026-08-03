# Mem0 Setup

The current host enables the on-demand `mem0-mcp-server` wrapper and uses an
embedded Qdrant database under `~/.local/share/mem0/qdrant`. The persistent
systemd service is configured but disabled.

## Current Mode

```nix
programs.mem0 = {
  enable = true;
  selfHosted = true;
  userId = "kosta";
};

services.mem0.enable = false;
```

Run the SSE server when needed:

```sh
mem0-mcp-server --host 127.0.0.1 --port 8050
```

The selected embedding and LLM providers still require their normal provider
credentials. Do not put plaintext keys in this repository.

## Persistent Service

To run Mem0 continuously, set `services.mem0.enable = true` in the host module.
Its provider configuration already points to the agenix-managed files:

```text
/run/secrets/voyage-api-key
/run/secrets/anthropic-api-key
```

When the service is enabled, the secrets module assigns those files to the
dedicated `mem0` account. Edit or rekey them with the workflow in `SECRETS.md`.

Verify the service with:

```sh
systemctl status mem0
journalctl -u mem0 -f
curl -N http://127.0.0.1:8050/sse
```

## Client Configuration

OpenCode SSE configuration:

```json
{
  "mcp": {
    "mem0": {
      "transport": "sse",
      "url": "http://127.0.0.1:8050/sse"
    }
  }
}
```

Claude Code:

```sh
claude mcp add mem0 --transport sse --url http://127.0.0.1:8050/sse
```

## Data Locations

- On-demand wrapper: `~/.local/share/mem0/qdrant`
- Persistent service: `/var/lib/mem0/qdrant`

# Mem0 Architecture

Mem0 remains disabled on rocinante. Its configuration supports two storage patterns without activating either one.

- `programs.mem0` provides an interactive MCP wrapper that can use an embedded local Qdrant data directory.
- `services.mem0` provides a system service that connects to a Qdrant HTTP endpoint through `services.mem0.qdrant.host` and `services.mem0.qdrant.port`.
- The native `services.qdrant` option provides an optional local Qdrant service. It is disabled by default.

Enable only the selected components after configuring API-key files and deciding whether the vector store is local or remote. A local Mem0 service starts after `qdrant.service` when `services.qdrant.enable = true`; a remote Qdrant endpoint requires no local service.

No Mem0 or Qdrant service is enabled by this flake's rocinante host configuration.

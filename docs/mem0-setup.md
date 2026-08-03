# Mem0 Setup

Mem0 is currently disabled. Its module remains available at
`modules/programs/mem0.nix`, but it installs no wrapper, starts no service, and
deploys no API secrets until explicitly enabled.

## Interactive User Mode

Enable the wrapper from the relevant user contribution:

```nix
nixos.modules.kosta = {
  programs.mem0 = {
    enable = true;
    selfHosted = true;
  };
};
```

When `programs.mem0.userId` is left null, the wrapper uses the runtime `$USER`.
It can be overridden with an explicit logical memory namespace when needed:

```nix
programs.mem0.userId = "shared-project";
```

Interactive mode stores embedded Qdrant data under
`~/.local/share/mem0/qdrant`. Provider credentials must be supplied in the
launch environment.

## Persistent Service

Enable the service from host policy because it owns a system account, port,
provider selection, and secret access:

```nix
services.mem0 = {
  enable = true;
  userId = "shared-project";
  port = 8050;

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

Here `userId` is the logical Mem0 namespace, not the operating-system service
account. The service itself always runs as the dedicated `mem0` account.

When enabled, agenix deploys the provider keys for that account and the service
listens on `http://127.0.0.1:8050/sse`. Data is stored under
`/var/lib/mem0/qdrant`.

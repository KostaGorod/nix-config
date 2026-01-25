# Helicone NixOS Module

## Quick Start: All-in-One

### 1. Add to your configuration

```nix
# configuration.nix
{ config, pkgs, ... }:
{
  imports = [
    ./modules/helicone/all-in-one.nix
  ];

  services.helicone-aio = {
    enable = true;
    port = 3000;
    openFirewall = true;  # Allow access from network
  };
}
```

### 2. Apply configuration

```bash
sudo nixos-rebuild switch
```

### 3. Wait for container to start

```bash
# Check container status
sudo docker ps | grep helicone

# Watch logs
sudo docker logs -f helicone

# Wait for "ready" message (takes 1-2 minutes on first start)
```

### 4. Test web panel

```bash
# Local test
curl -s http://localhost:3000 | head -20

# Or open in browser
xdg-open http://localhost:3000
```

### 5. Test from other hosts (via Tailscale)

```bash
# From another machine on your Tailscale network
curl -s http://<hostname>:3000

# Or use Tailscale IP
curl -s http://100.x.x.x:3000
```

## Test API Connectivity

### Send a test request through Helicone proxy

```bash
# Point to Helicone as OpenAI base URL
export OPENAI_API_BASE="http://localhost:3000/v1"
export OPENAI_API_KEY="your-actual-openai-key"

# Test with curl
curl -X POST http://localhost:3000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Helicone-Auth: Bearer your-helicone-api-key" \
  -d '{
    "model": "gpt-3.5-turbo",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

## Ports

| Port | Service |
|------|---------|
| 3000 | Web UI + API |

## Data Storage

All data stored in `/var/lib/helicone/`:
- `postgres/` - User data, API keys
- `clickhouse/` - Request logs, analytics
- `minio/` - Request/response storage

## Backup (simple)

```bash
# Stop container
sudo systemctl stop docker-helicone

# Backup data
sudo tar -czvf helicone-backup-$(date +%Y%m%d).tar.gz /var/lib/helicone

# Start container
sudo systemctl start docker-helicone
```

## Troubleshooting

```bash
# Container not starting?
sudo docker logs helicone

# Port in use?
sudo ss -tlnp | grep 3000

# Restart container
sudo systemctl restart docker-helicone

# Full reset (loses data!)
sudo systemctl stop docker-helicone
sudo rm -rf /var/lib/helicone/*
sudo systemctl start docker-helicone
```

## Next Steps

Once testing works:
1. Set proper `BETTER_AUTH_SECRET` (generate with `openssl rand -base64 32`)
2. Add Nginx reverse proxy with TLS
3. Configure backups
4. Point AI agents to Helicone endpoint

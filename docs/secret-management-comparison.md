# NixOS Secret Management Comparison

Comparing **agenix**, **sops-nix**, and **Bitwarden/Vaultwarden** for managing secrets at `/run/secrets/`.

---

## Quick Summary

| Feature | agenix | sops-nix | Bitwarden/Vaultwarden |
|---------|--------|----------|----------------------|
| **Encryption** | age | age, GPG, cloud KMS | AES-256 (server-side) |
| **Secrets in Git** | Yes (encrypted) | Yes (encrypted) | No (external vault) |
| **Setup Complexity** | Low | Medium | High |
| **Multi-machine** | Good (SSH keys) | Good (age keys) | Excellent (centralized) |
| **Runtime Dependencies** | None | None | Network + service |
| **Offline Support** | Full | Full | Limited |
| **Secret Rotation** | Manual rekey | Manual rekey | GUI/API |
| **NixOS Integration** | Native module | Native module | Requires wrapper |
| **Community Adoption** | High | Very High | Low (for this use case) |

---

## 1. agenix

**Repository:** https://github.com/ryantm/agenix

### How It Works
- Uses **age** encryption (modern, simple alternative to GPG)
- Encrypts secrets using SSH public keys (ed25519 or RSA)
- Secrets decrypted at system activation and placed in `/run/agenix/`
- Leverages existing SSH host keys - no extra key management

### Setup

```nix
# flake.nix
{
  inputs.agenix = {
    url = "github:ryantm/agenix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, agenix, ... }: {
    nixosConfigurations.rocinante = nixpkgs.lib.nixosSystem {
      modules = [
        agenix.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

```nix
# secrets.nix (in repo root)
let
  # SSH public keys for encryption
  rocinante = "ssh-ed25519 AAAAC3Nz..."; # from /etc/ssh/ssh_host_ed25519_key.pub
  kosta = "ssh-ed25519 AAAAC3Nz...";     # from ~/.ssh/id_ed25519.pub
in {
  "secrets/voyage-api-key.age".publicKeys = [ rocinante kosta ];
  "secrets/anthropic-api-key.age".publicKeys = [ rocinante kosta ];
}
```

```bash
# Create encrypted secret
cd /path/to/nix-config
agenix -e secrets/voyage-api-key.age
# Editor opens, paste secret, save
```

```nix
# configuration.nix
{
  age.secrets = {
    voyage-api-key = {
      file = ../secrets/voyage-api-key.age;
      path = "/run/secrets/voyage-api-key";  # Custom path
      owner = "root";
      group = "root";
      mode = "0400";
    };
    anthropic-api-key = {
      file = ../secrets/anthropic-api-key.age;
      path = "/run/secrets/anthropic-api-key";
    };
  };
}
```

### Pros
- **Simplest setup** - Uses existing SSH keys, no new key infrastructure
- **No runtime dependencies** - Decrypts at activation only
- **Familiar tooling** - SSH keys everyone already has
- **Lightweight** - Single binary, minimal code

### Cons
- **One secret per file** - Can't bundle multiple secrets in one encrypted file
- **SSH key management** - Need to track all machine/user SSH keys
- **Less flexible encryption** - Only age (though age is excellent)

---

## 2. sops-nix

**Repository:** https://github.com/Mic92/sops-nix

### How It Works
- Uses **SOPS** (Secrets OPerationS) by Mozilla
- Supports multiple encryption backends: age, GPG, AWS KMS, GCP KMS, Azure Key Vault
- Multiple secrets in a single YAML/JSON file
- Decrypted at activation to `/run/secrets/`

### Setup

```nix
# flake.nix
{
  inputs.sops-nix = {
    url = "github:Mic92/sops-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, sops-nix, ... }: {
    nixosConfigurations.rocinante = nixpkgs.lib.nixosSystem {
      modules = [
        sops-nix.nixosModules.sops
        ./configuration.nix
      ];
    };
  };
}
```

```bash
# Generate age key (one-time)
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
# Save the public key: age1xxxxxxxxx...
```

```yaml
# .sops.yaml (repo root)
keys:
  - &rocinante age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
  - &kosta age1yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy

creation_rules:
  - path_regex: secrets/.*\.yaml$
    key_groups:
      - age:
          - *rocinante
          - *kosta
```

```bash
# Create secrets file
sops secrets/secrets.yaml
```

```yaml
# secrets/secrets.yaml (after decryption in editor)
voyage-api-key: sk-voyage-xxxxx
anthropic-api-key: sk-ant-xxxxx
github-token: ghp_xxxxx
```

```nix
# configuration.nix
{
  sops = {
    defaultSopsFile = ../secrets/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    # Or use dedicated age key:
    # age.keyFile = "/var/lib/sops-nix/key.txt";

    secrets = {
      "voyage-api-key" = {
        path = "/run/secrets/voyage-api-key";
        owner = "root";
        mode = "0400";
      };
      "anthropic-api-key" = {
        path = "/run/secrets/anthropic-api-key";
      };
    };
  };
}
```

### Pros
- **Multiple secrets per file** - Organized, fewer files
- **Flexible encryption** - age, GPG, cloud KMS providers
- **Industry standard** - SOPS used beyond NixOS
- **Excellent documentation** - Large community, many examples
- **Key groups** - Require multiple keys for decryption (security)

### Cons
- **More complex setup** - `.sops.yaml` configuration, age key generation
- **Extra tooling** - Need `sops` CLI for editing
- **Slightly larger attack surface** - More code paths

---

## 3. Bitwarden/Vaultwarden Integration

**Vaultwarden:** https://github.com/dani-garcia/vaultwarden (self-hosted Bitwarden)

### How It Works
- Secrets stored in Bitwarden vault (cloud or self-hosted Vaultwarden)
- Retrieved at boot/activation via Bitwarden CLI
- Written to `/run/secrets/` by a systemd service
- Requires network access and running Vaultwarden server

### Setup

```nix
# flake.nix - add vaultwarden server (if self-hosting)
{
  services.vaultwarden = {
    enable = true;
    config = {
      DOMAIN = "https://vault.example.com";
      SIGNUPS_ALLOWED = false;
    };
  };
}
```

```nix
# Secret retrieval module
{ config, pkgs, lib, ... }:
let
  bw = "${pkgs.bitwarden-cli}/bin/bw";

  fetchSecret = name: itemId: ''
    ${bw} get item ${itemId} --session "$BW_SESSION" | \
      ${pkgs.jq}/bin/jq -r '.login.password' > /run/secrets/${name}
    chmod 0400 /run/secrets/${name}
  '';
in {
  # Create secrets directory
  systemd.tmpfiles.rules = [
    "d /run/secrets 0755 root root -"
  ];

  # Systemd service to fetch secrets at boot
  systemd.services.bitwarden-secrets = {
    description = "Fetch secrets from Bitwarden";
    wantedBy = [ "multi-user.target" ];
    before = [ "mem0.service" ];  # Before services that need secrets

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      EnvironmentFile = "/root/.bw-credentials";  # BW_CLIENTID, BW_CLIENTSECRET
    };

    script = ''
      export BW_SESSION=$(${bw} login --apikey --raw)
      ${bw} sync

      ${fetchSecret "voyage-api-key" "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"}
      ${fetchSecret "anthropic-api-key" "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"}

      ${bw} logout
    '';
  };
}
```

### Pros
- **Centralized management** - Single source of truth across all systems
- **GUI for non-technical users** - Web vault, browser extensions
- **Dynamic secrets** - Can update without rebuilding NixOS
- **Audit logging** - Track secret access (Bitwarden premium)
- **Sharing** - Easy to share secrets with team members
- **Mobile access** - View/manage secrets from phone

### Cons
- **Runtime dependency** - Requires network and Vaultwarden service
- **Bootstrap problem** - Need credentials to access credentials
- **Complexity** - More moving parts, more failure modes
- **Not NixOS-native** - Requires custom wrapper module
- **Offline failure** - System won't get secrets without network
- **Latency** - Network round-trip at boot

---

## Recommendation for Your Setup

Based on your current configuration (mem0.nix expecting `/run/secrets/`):

### For Simplicity: **agenix**
- Reuses your existing SSH keys
- Minimal configuration
- Perfect for single-user, few-machine setups

### For Flexibility: **sops-nix** (Already documented)
- Better for growing configurations
- Multiple secrets in one file
- Cloud KMS option for enterprise use
- You already have a migration guide at `docs/sops-nix-migration.md`

### For Centralized Management: **Bitwarden/Vaultwarden**
- Best if you already use Bitwarden for passwords
- Good for teams or many machines
- Requires more infrastructure

---

## Migration Path from Current State

Your current setup uses unencrypted files in `~/.config/nixos-secrets/`. Here's the quickest path to each:

### To agenix (Easiest)
```bash
# 1. Get SSH host public key
cat /etc/ssh/ssh_host_ed25519_key.pub

# 2. Create secrets.nix with that key

# 3. Encrypt existing secrets
agenix -e secrets/voyage-api-key.age
# Paste content from ~/.config/nixos-secrets/voyage-api-key

# 4. Add age.secrets to configuration.nix

# 5. Rebuild and verify, then delete old secrets
```

### To sops-nix
Follow existing guide at `docs/sops-nix-migration.md`

### To Bitwarden
```bash
# 1. Set up Vaultwarden or use Bitwarden cloud
# 2. Create items in vault for each secret
# 3. Create API key for CLI access
# 4. Implement systemd service module
# 5. Add service ordering dependencies
```

---

## File Permissions Reference

All three solutions support setting permissions on decrypted secrets:

```nix
# agenix
age.secrets.my-secret = {
  file = ./secret.age;
  path = "/run/secrets/my-secret";
  owner = "myservice";
  group = "myservice";
  mode = "0400";
};

# sops-nix
sops.secrets."my-secret" = {
  path = "/run/secrets/my-secret";
  owner = "myservice";
  group = "myservice";
  mode = "0400";
};

# Bitwarden (in script)
chown myservice:myservice /run/secrets/my-secret
chmod 0400 /run/secrets/my-secret
```

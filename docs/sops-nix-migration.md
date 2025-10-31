# sops-nix Migration Guide

## Current State
Currently using simple file-based secret management with `builtins.readFile` pointing to `~/.config/nixos-secrets/`.

**Pros:**
- Simple setup
- No additional dependencies
- Easy to understand

**Cons:**
- Secrets stored unencrypted on disk
- No way to safely commit secrets to git
- Manual backup required
- Doesn't scale well for multiple machines/users

---

## Future: Migrate to sops-nix

### Why sops-nix?
- **Encrypted secrets in git** - Safe to commit encrypted secrets
- **Per-user/machine encryption** - Each system has its own key
- **Industry standard** - Used by many in NixOS community
- **Automatic decryption** - Secrets decrypted at activation time
- **Multiple secrets support** - Easy to manage many secrets

### Migration Steps

#### 1. Add sops-nix to flake.nix

```nix
{
  inputs = {
    # ... existing inputs ...
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, home-manager, sops-nix, ... }: {
    nixosConfigurations.rocinante = nixpkgs.lib.nixosSystem {
      # ... existing config ...
    };

    homeConfigurations.kosta = home-manager.lib.homeManagerConfiguration {
      modules = [
        sops-nix.homeManagerModules.sops
        ./home-manager/home.nix
      ];
    };
  };
}
```

#### 2. Generate age encryption key

```bash
# Create age key
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt

# Get public key (you'll need this)
age-keygen -y ~/.config/sops/age/keys.txt
```

#### 3. Create .sops.yaml in repo root

```yaml
keys:
  - &kosta_rocinante age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx  # Your age public key

creation_rules:
  - path_regex: secrets/secrets\.yaml$
    key_groups:
      - age:
          - *kosta_rocinante
```

#### 4. Create encrypted secrets file

```bash
# Install sops if not already
nix-shell -p sops

# Create and edit secrets
sops secrets/secrets.yaml
```

Add secrets in YAML format:
```yaml
context7-api-key: c7-api-73c89a2a00e84b2295dfcf0fb6f3ef39
# Add more secrets as needed
```

#### 5. Update home-manager configuration

```nix
{ config, pkgs, ... }:
{
  # Enable sops
  sops = {
    defaultSopsFile = ../secrets/secrets.yaml;
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

    secrets = {
      context7-api-key = {
        # Secret will be available at runtime
      };
    };
  };

  programs.vscode = {
    # ... existing config ...
    profiles.default = {
      userSettings = {
        "mcpServers" = {
          "context7" = {
            "command" = "${pkgs-unstable.nodejs_22}/bin/npx";
            "args" = ["-y" "@context7/mcp-server"];
            "env" = {
              # Read from sops-decrypted secret
              "CONTEXT7_API_KEY" = builtins.readFile config.sops.secrets.context7-api-key.path;
            };
          };
        };
      };
    };
  };
}
```

#### 6. Update .gitignore

```gitignore
# Age private keys - NEVER commit!
.config/sops/age/keys.txt

# Encrypted secrets are SAFE to commit
# secrets/secrets.yaml  # This line should be REMOVED or commented
```

#### 7. Migrate existing secrets

```bash
# Copy current secret value
OLD_KEY=$(cat ~/.config/nixos-secrets/context7-api-key)

# Edit sops secrets file
sops secrets/secrets.yaml
# Add: context7-api-key: <paste value>

# Remove old secrets directory (after verifying everything works)
rm -rf ~/.config/nixos-secrets/
```

### Benefits After Migration
- ✅ Secrets safely backed up in git (encrypted)
- ✅ Easy to replicate configuration on new machines
- ✅ Can share configuration publicly without exposing secrets
- ✅ Automatic secret rotation support
- ✅ Per-environment secrets (dev/prod)

### Resources
- [sops-nix GitHub](https://github.com/Mic92/sops-nix)
- [sops-nix Wiki](https://github.com/Mic92/sops-nix/wiki)
- [age encryption](https://github.com/FiloSottile/age)

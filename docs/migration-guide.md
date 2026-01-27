# Modular NixOS Configuration Migration Guide

This guide explains the new modular structure introduced in the `refactor/flake-parts-modular-structure` branch and how to use it effectively.

## Overview

The refactoring converts the monolithic NixOS configuration into a modular system using `flake-parts` with clear separation of concerns:

- **System configuration** (hardware, boot, networking) → `hosts/<hostname>/`
- **User configuration** (packages, programs, services) → `users/<username>/`
- **Reusable profiles** (workstation, server, minimal) → `profiles/`
- **Reusable modules** (services, desktop, AI tools) → `modules/nixos/`

## Directory Structure

```
nix-config/
├── flake.nix                    # Main flake (uses flake-parts)
├── flake.lock                   # Lock file for all inputs
├── hosts/                       # System-specific configurations
│   └── rocinante/
│       └── default.nix          # rocinante system config (155 lines)
├── users/                       # User-specific configurations
│   └── kosta/
│       ├── default.nix           # User config aggregator
│       ├── packages.nix          # User packages
│       └── programs/
│           ├── git.nix           # Git settings
│           ├── shell.nix         # Shell configuration
│           ├── editors/          # Editor configurations
│           └── services.nix      # User services
├── profiles/                    # Reusable profiles
│   └── workstation.nix         # Full workstation profile
├── modules/                     # Reusable modules
│   └── nixos/
│       ├── services.nix          # Core services
│       ├── desktop.nix          # Desktop environment
│       ├── tailscale.nix        # Tailscale VPN
│       ├── utils.nix            # System utilities
│       ├── opencode.nix         # OpenCode MCP
│       ├── claude-code.nix      # Claude Code
│       ├── droids.nix           # Droids agents
│       ├── bitwarden.nix        # Bitwarden
│       └── abacusai.nix         # AbacusAI tools
└── flakes/                     # Nested flakes (isolated environments)
    ├── antigravity-fhs/
    ├── abacusai-fhs/
    ├── vibe-kanban/
    └── cosmic-unstable/
```

## Key Principles

### 1. Single Responsibility
Each file has one clear purpose:
- `hosts/rocinante/default.nix` → Only system-level configuration
- `users/kosta/packages.nix` → Only user packages
- `modules/nixos/services.nix` → Only service definitions

### 2. Separation of Concerns
- **System vs User**: Host configs manage hardware; user configs manage software
- **Reusable vs Specific**: Modules and profiles are reusable; hosts and users are specific
- **Core vs Optional**: Services and utils are core; AI tools are optional

### 3. Predictable Paths
Every file follows a consistent pattern:
- `hosts/<hostname>/default.nix` for systems
- `users/<username>/<category>.nix` for user configs
- `modules/nixos/<name>.nix` for NixOS modules

### 4. Import Tree Pattern
Configuration imports follow a clear hierarchy:
```
flake.nix
├── hosts/rocinante/default.nix
│   ├── modules/nixos/... (system modules)
│   ├── profiles/workstation.nix (optional)
│   └── users/kosta/default.nix
│       ├── packages.nix
│       └── programs/...
```

## Adding a New Host

1. Create host directory:
   ```bash
   mkdir -p hosts/my-new-host
   ```

2. Create `hosts/my-new-host/default.nix`:
   ```nix
   { config, lib, pkgs, modulesPath, inputs, ... }:
   {
     imports = [
       ./hardware.nix  # Hardware-specific config (if any)

       # Core system modules
       ../../modules/nixos/services.nix
       ../../modules/nixos/utils.nix

       # Optional: Include profiles
       ../../profiles/workstation.nix
     ];

     # Boot configuration
     boot.loader.systemd-boot.enable = true;

     # Networking
     networking.hostName = "my-new-host";

     # User setup (groups only, no packages)
     users.users.kosta = {
       isNormalUser = true;
       extraGroups = [ "wheel" "networkmanager" "docker" ];
     };

     # Home Manager
     home-manager.users.kosta = {
       imports = [ ../../users/kosta/default.nix ];
     };
   }
   ```

3. Add to `flake.nix`:
   ```nix
   flake.nix: (in perSystem -> packages -> nixosConfigurations)
   my-new-host = nixpkgs.lib.nixosSystem {
     specialArgs = { inherit inputs; };
     modules = [
       ./hosts/my-new-host/default.nix
       inputs.home-manager.nixosModules.home-manager
       {
         home-manager = {
           useGlobalPkgs = true;
           useUserPackages = true;
           extraSpecialArgs = { inherit inputs; };
         };
       }
     ];
   };
   ```

4. Build and switch:
   ```bash
   nixos-rebuild switch --flake .#my-new-host
   ```

## Adding a New User

1. Create user directory:
   ```bash
   mkdir -p users/alice
   ```

2. Create `users/alice/default.nix`:
   ```nix
   { config, pkgs, ... }:
   {
     home.username = "alice";
     home.homeDirectory = "/home/alice";
     home.stateVersion = "24.05";

     imports = [
       ./packages.nix
       ./programs/git.nix
       ./programs/shell.nix
     ];
   }
   ```

3. Create `users/alice/packages.nix`:
   ```nix
   { pkgs, ... }:
   {
     home.packages = with pkgs; [
       neovim
       git
       htop
     ];
   }
   ```

4. Add to host config:
   ```nix
   # In hosts/your-host/default.nix
   users.users.alice = {
     isNormalUser = true;
     extraGroups = [ "wheel" ];
   };

   home-manager.users.alice = {
     imports = [ ../../users/alice/default.nix ];
   };
   ```

## Creating a New Profile

Profiles bundle multiple modules together for specific use cases.

**Example: `profiles/laptop.nix`**
```nix
{ ... }:
{
  imports = [
    ../modules/nixos/services.nix
    ../modules/nixos/desktop.nix
    ../modules/nixos/tailscale.nix
  ];

  # Laptop-specific settings
  services.tlp.enable = true;
  powerManagement.enable = true;
}
```

Use in host config:
```nix
imports = [
  ../../profiles/laptop.nix  # Instead of importing modules individually
];
```

## Creating a New Module

Modules are reusable NixOS configuration snippets.

**Example: `modules/nixos/development.nix`**
```nix
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    git
    gh
    docker
    kubectl
    nodejs
  ];

  # Enable services
  virtualisation.docker.enable = true;
}
```

Use in host or profile:
```nix
imports = [
  ../../modules/nixos/development.nix
];
```

## Modifying Existing Configurations

### Adding a Package to a User
Edit `users/kosta/packages.nix`:
```nix
home.packages = with pkgs; [
  # ... existing packages
  new-package-here  # Add this
];
```

### Adding a System Service
Edit `modules/nixos/services.nix` (or create new module):
```nix
services.new-service = {
  enable = true;
  settings = { ... };
};
```

### Updating Host Hardware
Edit `hosts/rocinante/default.nix` hardware section:
```nix
boot.initrd.availableKernelModules = [
  "new-kernel-module"  # Add this
];
```

## Testing Changes

1. **Check syntax**:
   ```bash
   nix flake check
   ```

2. **Format code**:
   ```bash
   nix fmt
   ```

3. **Build only** (without switching):
   ```bash
   nixos-rebuild build --flake .#rocinante
   ```

4. **Build and switch** (apply changes):
   ```bash
   sudo nixos-rebuild switch --flake .#rocinante
   ```

## Common Patterns

### Conditionally Enable Modules
```nix
# In host config
imports = lib.optional (config.networking.hostName == "rocinante")
  ../../modules/nixos/gaming.nix;
```

### Override Settings
```nix
# Override profile defaults in host config
services.tailscale.useRoutingFeatures = "both";  # Override profile setting
```

### Add Module-Specific Packages
```nix
# In module
{ config, pkgs, ... }:
{
  config = {
    home.packages = with pkgs; [
      module-specific-package
    ];
  };
}
```

## Migration from Old Structure

### Before (Monolithic)
```nix
# hosts/rocinante/configuration.nix (400+ lines)
{ config, pkgs, ... }:
{
  # Hardware
  boot.loader.grub.device = "/dev/sda";

  # Networking
  networking.hostName = "rocinante";

  # Packages (mixed system/user)
  environment.systemPackages = with pkgs; [
    vim
    steam
    code-cursor
    spotify
  ];

  # User config mixed in
  users.users.kosta.packages = with pkgs; [
    zed
  ];

  # Services mixed with desktop
  services.printing.enable = true;
  services.xserver.enable = true;

  # AI tools mixed in
  services.opencode.enable = true;
}
```

### After (Modular)
```nix
# hosts/rocinante/default.nix (155 lines)
{ config, ... }:
{
  imports = [
    ../../profiles/workstation.nix  # Pulls in desktop, services, AI tools
  ];

  # Only hardware and system settings
  boot.loader.grub.device = "/dev/sda";
  networking.hostName = "rocinante";
}

# profiles/workstation.nix (23 lines)
{ ... }:
{
  imports = [
    ../modules/nixos/desktop.nix
    ../modules/nixos/services.nix
    ../modules/nixos/opencode.nix
    ../modules/nixos/claude-code.nix
  ];
}

# modules/nixos/desktop.nix
{ config, ... }:
{
  services.xserver.enable = true;
  # Only desktop-related config
}
```

## Troubleshooting

### Module Not Found
**Error**: `error: path not found: modules/nixos/mymodule.nix`

**Solution**: Ensure the file exists and the import path is correct relative to the importing file.

### Circular Import
**Error**: `infinite recursion encountered`

**Solution**: Check that modules don't import each other. Use profiles to bundle modules instead.

### NixOS Rebuild Fails
**Error**: `error: attribute 'xyz' missing`

**Solution**:
1. Run `nix flake check` to verify syntax
2. Check that all imports have correct paths
3. Ensure nested flakes have their own `flake.nix`

## Best Practices

1. **Keep files small**: Files should be under 100 lines when possible
2. **One concern per file**: Don't mix services and packages in one file
3. **Use profiles**: Bundle commonly-used module combinations
4. **Test incrementally**: Build after each significant change
5. **Document**: Add comments explaining non-obvious configurations
6. **Version control**: Commit frequently with clear messages

## Tools Used

- **flake-parts**: Provides modular flake structure
- **treefmt**: Automatic code formatting (nixfmt, deadnix, statix)
- **nixfmt**: Nix language formatter
- **deadnix**: Detects dead code
- **statix**: Linter for Nix

## Further Reading

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Flake Parts](https://flake.parts/)
- [Home Manager](https://nix-community.github.io/home-manager/)
- [Nix Pills](https://nixos.org/guides/nix-pills/)

## Support

For issues or questions about this modular structure:
1. Check this guide for similar patterns
2. Review existing modules in `modules/nixos/`
3. Examine host configs in `hosts/`
4. Look at user configs in `users/`

# Nix Config Overhaul Plan

**Goal**: Restructure nix-config for readability, maintainability, and agent-first development using flake-parts + import-tree pattern.

**Strategy**: Strategy 1 (flake-parts + import-tree) - lowest friction, familiar structure, auto-discovery.

---

## Phase 0: Infrastructure Setup (Foundation)

### Task 0.1: Add flake-parts and tooling inputs
**File**: `flake.nix`
**Changes**:
- Add `flake-parts` input
- Add `import-tree` input  
- Add `treefmt-nix` input (for `nix fmt`)
- Keep all existing inputs

### Task 0.2: Create directory structure
**Action**: Create new directories
```
mkdir -p modules/nixos
mkdir -p modules/home-manager
mkdir -p users/kosta/programs
mkdir -p profiles
```

### Task 0.3: Add treefmt configuration
**File**: `treefmt.nix` (new)
**Content**: Configure nixfmt-rfc-style, deadnix, statix for linting

---

## Phase 1: Extract Host Settings (System-Level)

### Task 1.1: Create host default.nix
**Source**: `hosts/rocinante/configuration.nix` (458 lines)
**Target**: `hosts/rocinante/default.nix` (new, ~150 lines)
**Extract ONLY**:
- Boot/kernel config (lines 54-58)
- Networking (lines 59-80)
- Virtualization (lines 82-85)
- Hardware (bluetooth, logitech, graphics - lines 91-96, 415-425)
- Locale/timezone (lines 98-117)
- Power management/TLP (lines 185-222)
- User account definitions (WITHOUT packages) (lines 264-267)
- System-wide settings (stateVersion, nix settings)

### Task 1.2: Create system services module
**Target**: `modules/nixos/services.nix`
**Extract from configuration.nix**:
- `services.fwupd` (line 88)
- `services.printing` + `services.avahi` (lines 133-158)
- `services.pipewire` (lines 162-171)
- `services.locate` (lines 178-183)
- `services.tlp` (lines 187-222)
- `services.teamviewer` (line 390)

### Task 1.3: Create desktop environment module
**Target**: `modules/nixos/desktop.nix`
**Extract**:
- Fonts (lines 314-319)
- Cursor themes, calculator, virtual keyboard (lines 346-350)
- Graphics/Vulkan (lines 415-425)
- Session variables (lines 423-425)

### Task 1.4: Consolidate AI tools module
**Target**: `modules/nixos/ai-tools.nix`
**Merge existing**:
- `modules/opencode.nix`
- `modules/claude-code.nix`
- `modules/droids.nix`
- `modules/codex.nix`
- `modules/abacusai.nix`
**Pattern**: Single module with sub-options
```nix
options.programs.ai-tools = {
  opencode.enable = mkEnableOption "...";
  claude-code.enable = mkEnableOption "...";
  droids.enable = mkEnableOption "...";
  # etc
};
```

### Task 1.5: Keep tailscale module as-is
**File**: `modules/tailscale.nix` -> `modules/nixos/tailscale.nix`
**Action**: Move, no changes needed (already well-structured)

---

## Phase 2: Extract User Packages

### Task 2.1: Move user packages from configuration.nix
**Source**: `hosts/rocinante/configuration.nix` lines 268-309
**Target**: `users/kosta/packages.nix`
**Packages to move**:
- `_1password-gui`
- `firefox`
- `kdePackages.kdeconnect-kde`
- `kdePackages.plasma-browser-integration`
- `pciutils`
- `remmina`
- `code-cursor`
- `onlyoffice-desktopeditors`
- `vivaldi` (with override)
- Antigravity IDE (from inputs)
- Warp terminal (from inputs)

### Task 2.2: Keep home.nix packages in place
**File**: `home-manager/home.nix` -> `users/kosta/packages.nix`
**Merge packages from home.nix**:
- `zed-editor`, `fastfetch`, `nnn`
- `obsidian`, `todoist-electron`
- `kubectl`, `k9s`, `lens`
- `discord`, `slack`
- `deluge-gtk`, `dragon`
- `zen-browser`

---

## Phase 3: Extract User Preferences

### Task 3.1: Create git preferences
**Target**: `users/kosta/programs/git.nix`
**Extract from home.nix** (lines 149-164):
- `programs.git` config
- `programs.git-credential-oauth`
- `programs.gh`

### Task 3.2: Create shell preferences
**Target**: `users/kosta/programs/shell.nix`
**Extract from home.nix** (lines 167-177, 227-248):
- `programs.bash`
- `programs.starship`
- `programs.direnv`
- `programs.carapace`

### Task 3.3: Create editor preferences
**Target**: `users/kosta/programs/editors.nix`
**Extract from home.nix** (lines 116-146, 197-223, 257-277):
- `programs.vscode`
- `programs.helix`
- `programs.zed-editor`

### Task 3.4: Create SSH/services preferences
**Target**: `users/kosta/programs/services.nix`
**Extract from home.nix** (lines 251-254):
- `services.ssh-agent`

### Task 3.5: Create user default.nix
**Target**: `users/kosta/default.nix`
**Content**: Import all sub-modules
```nix
{ ... }:
{
  imports = [
    ./packages.nix
    ./programs/git.nix
    ./programs/shell.nix
    ./programs/editors.nix
    ./programs/services.nix
  ];
  
  home.stateVersion = "24.05";
  programs.home-manager.enable = true;
}
```

---

## Phase 4: Create Profiles

### Task 4.1: Create workstation profile
**Target**: `profiles/workstation.nix`
**Content**: Bundle for desktop workstations
```nix
{ ... }:
{
  imports = [
    ../modules/nixos/desktop.nix
    ../modules/nixos/services.nix
    ../modules/nixos/ai-tools.nix
  ];
  
  # Enable workstation defaults
  programs.ai-tools.opencode.enable = true;
  programs.ai-tools.claude-code.enable = true;
  programs.steam.enable = true;
}
```

---

## Phase 5: Migrate flake.nix

### Task 5.1: Convert to flake-parts
**File**: `flake.nix`
**Changes**:
```nix
{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    # ... existing inputs ...
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];
      
      imports = [
        inputs.treefmt-nix.flakeModule
      ];
      
      perSystem = { pkgs, ... }: {
        treefmt = {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
          programs.deadnix.enable = true;
          programs.statix.enable = true;
        };
      };
      
      flake = {
        nixosConfigurations.rocinante = inputs.nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/rocinante
            ./profiles/workstation.nix
            (inputs.import-tree ./modules/nixos)
            
            inputs.disko.nixosModules.disko
            inputs.home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = { inherit inputs; };
                users.kosta = import ./users/kosta;
              };
            }
          ];
        };
      };
    };
}
```

---

## Phase 6: Cleanup

### Task 6.1: Remove deprecated files
**Delete**:
- `modules/editors.nix` (duplicates helix, merged into user prefs)
- `modules/utils.nix` (merge into host or keep as system-utils)

### Task 6.2: Update .gitignore
**Add**:
```
result
.direnv/
```

### Task 6.3: Validate and test
**Commands**:
```bash
nix flake check
nix fmt
nixos-rebuild build --flake .#rocinante
```

---

## Final Directory Structure

```
nix-config/
├── flake.nix                    # flake-parts based
├── flake.lock
├── treefmt.nix
├── hosts/
│   └── rocinante/
│       ├── default.nix          # System config only
│       ├── hardware-configuration.nix
│       └── disko-config.nix
├── users/
│   └── kosta/
│       ├── default.nix          # Imports all below
│       ├── packages.nix         # User packages
│       └── programs/
│           ├── git.nix
│           ├── shell.nix
│           ├── editors.nix
│           └── services.nix
├── modules/
│   └── nixos/
│       ├── ai-tools.nix         # Consolidated AI tools
│       ├── tailscale.nix
│       ├── desktop.nix
│       └── services.nix
├── profiles/
│   └── workstation.nix
├── de/
│   └── plasma6.nix              # Keep as-is
├── flakes/                      # Keep as-is (local packages)
│   ├── warp-fhs/
│   ├── antigravity-fhs/
│   ├── abacusai-fhs/
│   ├── vibe-kanban/
│   ├── cosmic-unstable/
│   ├── claude-code/
│   └── droids/
└── environments/                # Keep as-is
    └── mikrotik/
```

---

## Execution Order

1. **Phase 0** - Foundation (can't break anything)
2. **Phase 5.1** - Convert flake.nix first (enables incremental migration)
3. **Phase 1** - Extract host settings
4. **Phase 2** - Extract user packages
5. **Phase 3** - Extract user preferences
6. **Phase 4** - Create profiles
7. **Phase 6** - Cleanup and validate

---

## Rollback Strategy

Keep original files with `.bak` suffix until `nixos-rebuild switch` succeeds:
```bash
cp hosts/rocinante/configuration.nix hosts/rocinante/configuration.nix.bak
cp home-manager/home.nix home-manager/home.nix.bak
cp flake.nix flake.nix.bak
```

After successful switch, delete `.bak` files.

---

## Agent-Friendly Conventions

1. **Predictable paths**: `modules/nixos/<feature>.nix`, `users/<name>/programs/<tool>.nix`
2. **One concern per file**: Each file does ONE thing
3. **Enable patterns**: All features use `enable = mkEnableOption` for discoverability
4. **Auto-import**: New modules auto-discovered, no manual flake.nix edits
5. **Consistent namespaces**: `programs.ai-tools.*`, `services.vibe-kanban.*`

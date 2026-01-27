# Testing Strategy for NixOS Modular Configuration

This document explains the testing approach for the modular NixOS configuration using flake-parts architecture.

## Overview

The testing strategy focuses on **fast feedback loops** while validating critical components:

1. **Quick checks** - Syntax and formatting (seconds)
2. **Module evaluation** - Independent module validation (seconds)
3. **Host builds** - Full system configuration (minutes)
4. **CI automation** - GitHub Actions pipeline

## Test Categories

### Priority 1: Critical Infrastructure (Must Pass)
These tests validate the system can boot and function:

| Component | Test | Time | Risk |
|-----------|-------|------|------|
| Boot configuration | `nix eval .#nixosConfigurations.rocinante.config.boot` | <1s | Critical |
| Disk configuration | Manual validation required | - | Critical |
| User accounts | `nix eval .#nixosConfigurations.rocinante.config.users` | <1s | Critical |
| Network config | `nix eval .#nixosConfigurations.rocinante.config.networking` | <1s | Critical |

### Priority 2: Core Services (Should Pass)
System-level services that enable functionality:

| Component | Test | Time | Risk |
|-----------|-------|------|------|
| Services module | `nix-instantiate --parse modules/nixos/services.nix` | <1s | High |
| Tailscale | `nix-instantiate --parse modules/nixos/tailscale.nix` | <1s | High |
| Networking | Host configuration build | <1s | High |
| Desktop | `nix-instantiate --parse modules/nixos/desktop.nix` | <1s | Medium |

### Priority 3: User Configuration (Should Pass)
Home Manager and user-specific settings:

| Component | Test | Time | Risk |
|-----------|-------|------|------|
| User packages | `nix-instantiate --parse users/kosta/packages.nix` | <1s | Medium |
| User programs | `nix-instantiate --parse users/kosta/programs/*.nix` | <1s | Low |
| Home Manager | `nix build .#nixosConfigurations.rocinante.config.home-manager` | ~30s | Medium |

### Priority 4: Optional Features (Nice to Have)
AI tools, specialized applications, optional services:

| Component | Test | Time | Risk |
|-----------|-------|------|------|
| OpenCode | `nix-instantiate --parse modules/nixos/opencode.nix` | <1s | Low |
| Claude Code | `nix-instantiate --parse modules/nixos/claude-code.nix` | <1s | Low |
| Other AI tools | `nix-instantiate --parse modules/nixos/*.nix` | <1s | Low |

## Running Tests Locally

### All Quick Checks
```bash
# Syntax and formatting
nix flake check
nix fmt --check
nix run nixpkgs#deadnix -- .
nix run nixpkgs#statix check .
```

### Module Evaluation
```bash
# Critical modules
nix-instantiate --parse modules/nixos/services.nix
nix-instantiate --parse modules/nixos/tailscale.nix
nix-instantiate --parse modules/nixos/desktop.nix

# All modules
for module in modules/nixos/*.nix; do
  echo "Testing $module..."
  nix-instantiate --parse "$module" > /dev/null
done
```

### Host Build
```bash
# Dry run build (doesn't switch)
nixos-rebuild build --flake .#rocinante
```

### Using Flake Checks
```bash
# Run all checks defined in flake.nix
nix flake check

# Build specific check
nix build .#checks.x86_64-linux.treefmt
nix build .#checks.x86_64-linux.rocinante
```

## GitHub Actions CI Pipeline

The CI pipeline runs on every push and pull request with these jobs:

### Job 1: `checks` (Always runs)
- `nix flake check` - Syntax validation
- `nix fmt --check` - Formatting check
- `deadnix` - Dead code detection
- `statix` - Linting
- **Time**: ~1-2 minutes

### Job 2: `eval-modules` (After checks)
- Evaluates critical modules (services, tailscale)
- Evaluates optional modules (desktop, utils, AI tools)
- Tests module imports don't conflict
- **Time**: ~30 seconds

### Job 3: `eval-profiles` (After checks)
- Evaluates workstation profile
- Checks profile imports
- **Time**: ~30 seconds

### Job 4: `eval-users` (After checks)
- Evaluates user packages
- Evaluates user programs (git, shell, editors, services)
- Checks user default config
- **Time**: ~30 seconds

### Job 5: `build-host` (After checks + eval-modules)
- Builds full rocinante configuration
- Checks Home Manager activation
- **Time**: ~5-10 minutes (with caching)

### Job 6: `critical-checks` (After checks + eval-modules)
- Validates flake outputs exist
- Tests boot configuration
- Tests networking configuration
- Checks user configuration exists
- **Time**: ~1 minute

### Caching Strategy
- Uses Cachix for Nix store caching
- Cache key based on flake.lock
- Speeds up rebuilds by 80%+

## Test Failure Handling

### Syntax Errors
**Symptom**: `nix flake check` fails
**Action**: Fix syntax errors before committing
**Command**: `nix flake check --show-trace`

### Formatting Issues
**Symptom**: `nix fmt --check` fails
**Action**: Run `nix fmt` to auto-format
**Command**: `nix fmt`

### Module Conflicts
**Symptom**: `eval-modules` job fails
**Action**: Check module imports, look for overlapping configurations
**Debug**: `nix eval --raw --expr 'import <nixpkgs/lib>' --apply 'lib: lib.evalModules { modules = [...] }.config'`

### Build Failures
**Symptom**: `build-host` job fails
**Action**:
1. Check if dependencies changed in flake.lock
2. Verify all module paths are correct
3. Look for circular imports
4. Check package availability in nixpkgs

### Home Manager Issues
**Symptom**: Home Manager activation fails
**Action**: Check user config syntax and imports
**Debug**: `nix build .#nixosConfigurations.rocinante.config.home-manager.users.kosta.home.activationPackage`

## Pre-Commit Testing

Use pre-commit hooks to catch issues before pushing:

```bash
# Using pre-commit framework
cat > .pre-commit-config.yaml << 'EOF'
repos:
  - repo: local
    hooks:
      - id: nix-flake-check
        name: Nix flake check
        entry: nix flake check
        language: system
      - id: nix-fmt
        name: Nix format
        entry: nix fmt --check
        language: system
EOF

pre-commit install
```

## Adding New Tests

### Adding a New Module Test
1. Add module to `modules/nixos/`
2. Add test to `eval-modules` job in `.github/workflows/test.yml`
3. Optionally add to `flake.nix` `checks.eval-modules`

### Adding a New Host Test
1. Create host directory in `hosts/`
2. Add host to matrix in `build-host` job
3. Add host-specific validation to `critical-checks` job

### Adding a New User Test
1. Create user directory in `users/`
2. Add evaluation tests to `eval-users` job
3. Add package list validation

## Testing Best Practices

1. **Test Early, Test Often** - Run quick checks after every change
2. **Use Flake Checks** - Define tests in `flake.nix` for local validation
3. **Cache Builds** - Use Cachix to speed up CI
4. **Parallel Jobs** - CI runs independent tests in parallel
5. **Fail Fast** - Quick checks run before expensive builds
6. **Test Independently** - Each module should validate alone
7. **Mock When Needed** - Use `nix eval` instead of full builds when possible

## Continuous Improvement

The testing strategy should evolve as the configuration grows:

- **Add new tests** as new modules are created
- **Refactor tests** when the structure changes
- **Monitor CI times** and optimize slow jobs
- **Add integration tests** for complex interactions
- **Consider VM testing** for critical changes (boot, disk)

## Resources

- [NixOS Testing Guide](https://nixos.org/manual/nixos/stable/#sec-testing)
- [Flake Testing Patterns](https://github.com/NixOS/nixpkgs/blob/master/.github/workflows)
- [Nix Language Tests](https://nixos.org/manual/nix/stable/language.html)
- [CI/CD Examples](https://github.com/search?q=language%3AYAML+nixos+workflow+type%3Aworkflow)

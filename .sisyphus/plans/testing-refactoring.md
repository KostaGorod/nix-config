# Testing Refactoring Plan

## Problem Statement

Current testing infrastructure has significant duplication and poor locality:

### Duplication Issues
1. **flake.nix checks** - Duplicate check definitions (lines 115-136, repeated in diff)
2. **CI workflow tests** - Same nix-instantiate commands repeated for different file categories
3. **Separated concerns** - Test logic lives in 2 places (flake.nix + GitHub Actions)

### Locality Issues
1. **Tests far from source** - Test logic in flake.nix and .github/workflows/, files tested in modules/hosts/users/
2. **tests/ directory unused** - Created but empty, no actual test files
3. **No test-per-file pattern** - Can't add test alongside module easily

## Solution Design

### Principle 1: Abstract Common Testing Resources

Create reusable Nix functions that eliminate duplication:

**`lib/tests.nix`** - Testing utilities library
```nix
{ pkgs, lib, ... }:

{
  # Abstract: Parse and validate Nix file
  validateNixFile = path:
    pkgs.runCommand "check-${builtins.baseNameOf path}" { buildInputs = [ pkgs.nix ]; } ''
      ${pkgs.nix}/bin/nix-instantiate --parse ${path} > /dev/null
      touch $out
    '';

  # Abstract: Validate multiple files as one test
  validateFiles = files: name:
    pkgs.runCommand name { buildInputs = [ pkgs.nix ]; } ''
      ${lib.concatMapStringsSep "\n" (file: ''
        ${pkgs.nix}/bin/nix-instantiate --parse ${file} > /dev/null
      '') files}
      touch $out
    '';

  # Abstract: Test module can be evaluated
  evalModule = module:
    lib.evalModules { modules = [ module ]; } != null;
}
```

### Principle 2: Tests Close to Source

Place test files alongside their sources:

```
modules/nixos/
├── services.nix
├── services.nix.test.nix          # Test file next to source
├── tailscale.nix
├── tailscale.nix.test.nix
├── desktop.nix
├── desktop.nix.test.nix
└── utils.nix
    └── utils.nix.test.nix

hosts/rocinante/
├── default.nix
├── default.nix.test.nix
└── disko-config.nix
    └── disko-config.nix.test.nix

users/kosta/
├── packages.nix
├── packages.nix.test.nix
└── programs/
    ├── git.nix
    ├── git.nix.test.nix
    └── ...
```

### Principle 3: Test File Convention

Each `*.nix.test.nix` exports test attributes:

```nix
# modules/nixos/services.nix.test.nix
{ pkgs, lib, ... }:

let
  # Import the module being tested
  module = import ./services.nix;
in
{
  # Test attributes
  checks = {
    # Syntax validation (always run)
    syntax = pkgs.nix-instantiate --parse ./services.nix > /dev/null;

    # Module evaluation (always run)
    eval = lib.evalModules { modules = [ module ]; };

    # Custom assertions (optional)
    expectedPackages = builtins.elem "fwupd" module.config.environment.systemPackages;
  };
}
```

### Principle 4: Auto-discover Tests

Create test runner that finds `*.test.nix` files:

```nix
# tests/runner.nix
{ pkgs, lib, ... }:

let
  # Find all test files
  findAllTests = path:
    builtins.filter (f: lib.hasSuffix ".test.nix" f)
      (lib.filesystem.listFilesRecursive path);

  # Load and run test
  runTest = testFile:
    import testFile { inherit pkgs lib; };

  # Test categories by priority
  critical = findAllTests ./modules/nixos;
  hosts = findAllTests ./hosts;
  users = findAllTests ./users;
in
{
  checks = {
    # Run all tests by category
    critical-tests = builtins.map runTest critical;
    host-tests = builtins.map runTest hosts;
    user-tests = builtins.map runTest users;
  };
}
```

## Implementation Plan

### Phase 1: Create Testing Library
**Create** `lib/tests.nix` with reusable test utilities:
- `validateNixFile` - Single file syntax check
- `validateFiles` - Batch file checks
- `evalModule` - Module evaluation helper
- `assertModuleConfig` - Configuration assertion helper

**Update** `flake.nix` to import and use test library

### Phase 2: Create Test Files Near Sources
**Create** test files for critical modules:
- `modules/nixos/services.nix.test.nix`
- `modules/nixos/tailscale.nix.test.nix`
- `modules/nixos/desktop.nix.test.nix`

**Create** test files for host/user configs:
- `hosts/rocinante/default.nix.test.nix`
- `users/kosta/packages.nix.test.nix`
- `profiles/workstation.nix.test.nix`

### Phase 3: Simplify flake.nix
**Remove** duplicate check definitions from `flake.nix`

**Replace** with:
```nix
checks = {
  # Auto-discover and run all *.test.nix files
  all-tests = import ./tests/runner.nix { inherit pkgs lib; };

  # Critical path validation (can't be tested per-file)
  critical-paths-exist = pkgs.runCommand "check-paths" { } ''
    test -f ./modules/nixos/services.nix
    test -f ./modules/nixos/tailscale.nix
    test -f ./hosts/rocinante/default.nix
    test -f ./users/kosta/default.nix
    touch $out
  '';
}
```

### Phase 4: Simplify CI Workflow
**Replace** duplicate test jobs with test runner:

```yaml
build-and-test:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: cachix/install-nix-action@v25
    - uses: cachix/cachix-action@v14

    # Run all tests via test runner
    - name: Run all tests
      run: nix build .#checks.x86_64-linux.all-tests

    # Build configuration only if tests pass
    - name: Build configuration
      run: nix build .#nixosConfigurations.rocinante.config.system.build.toplevel
```

### Phase 5: Documentation and Examples
**Create** `tests/README.md`:
- How to write `*.test.nix` files
- Available test utilities from `lib/tests.nix`
- Examples of common test patterns
- Running tests locally and in CI

**Update** `docs/testing-strategy.md`:
- Reflect new test-per-file pattern
- Remove duplication explanation
- Show examples of adding new tests

## Benefits

### Before
- 50+ lines of duplicated test logic
- Tests in 2 separate locations
- No obvious place to add test for new file
- CI and flake tests out of sync

### After
- Single source of truth for test utilities
- Tests live next to code they test
- Adding test = create `*.test.nix` alongside file
- CI and local tests use same runner
- Auto-discovery of all tests

## Success Criteria

1. ✅ `lib/tests.nix` provides reusable test utilities
2. ✅ Critical modules have `*.test.nix` files alongside them
3. ✅ `flake.nix` reduced to ~20 lines for tests
4. ✅ CI workflow uses test runner (no duplication)
5. ✅ Running `nix flake check` discovers and runs all tests
6. ✅ Adding new test = copy pattern from existing file

## Migration Path

1. Create `lib/tests.nix` (no breaking changes)
2. Add test files for critical modules (non-breaking)
3. Update CI workflow to use test runner (parallel)
4. Remove old test logic from flake.nix (cleanup)
5. Update documentation (reflect new pattern)

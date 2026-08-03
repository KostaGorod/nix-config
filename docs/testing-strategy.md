# Testing Strategy

The flake exposes formatting and `rocinante` build checks through flake-parts.
There is no Home Manager configuration or standalone module-test matrix.

## Required Checks

Run these commands after configuration changes:

```sh
nix fmt
nix flake check --no-build
nix build .#checks.x86_64-linux.rocinante-toplevel
```

- `nix fmt` runs nixfmt, deadnix, and statix through treefmt.
- `nix flake check --no-build` evaluates every flake output without building it.
- The explicit build realizes the complete `rocinante` NixOS closure.

The host check is intentionally exposed only for `x86_64-linux`. Treefmt remains
available for every system listed in `aspects/tooling.nix`.

## Focused Evaluation

Use these commands for quick investigation:

```sh
nix eval .#nixosConfigurations.rocinante.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.rocinante.config.networking.hostName
nix eval .#nixosConfigurations.rocinante.config.users.users.kosta.packages \
  --apply 'packages: map (package: package.name) packages'
```

Individual Nix files can be parsed with `nix-instantiate --parse`, but parsing a
module does not validate its options or its interaction with the complete system.
The flake evaluation and host build are authoritative.

## CI

`.github/workflows/test.yml` runs the flake checks, builds the `rocinante`
toplevel, and builds the treefmt check. Local verification should use the same
commands before a change is committed.

## Failure Diagnosis

For evaluation errors:

```sh
nix flake check --no-build --show-trace
```

For build errors:

```sh
nix build .#checks.x86_64-linux.rocinante-toplevel --print-build-logs
```

For formatting or static-analysis errors, run `nix fmt` and inspect its output.

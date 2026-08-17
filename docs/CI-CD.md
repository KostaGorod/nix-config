# CI/CD and Branch Flow

The repository uses a one-way branch sync model with three GitHub Actions
workflows. `main` is the release branch; `develop` is the integration branch.

## Branch flow

```text
features   → PR into develop          (Nix Checks run on the PR)
hotfix     → commit/PR into main
             └─ push to main triggers "Rebase develop onto main"
pin bot    → daily: resolve pins → full validation in-workflow
             (flake check + rocinante build) → push to main only if green
promotion  → develop into main when ready
             (fast-forward, because sync guarantees main ⊆ develop)
```

The sync invariant is: **`main` is always an ancestor of `develop`.** After a
promotion (`develop → main`), `develop` is already at or past `main`, so the
sync workflow no-ops. After a hotfix or bot pin update on `main`, the sync
workflow fast-forwards or rebases `develop` onto it.

`main` is never force-pushed or rewritten. `develop` may be rewritten by the
sync workflow (rebase + `--force-with-lease`); only the sync workflow does
this.

## Workflows

### Nix Checks (`test.yml`)

Runs on pushes to `main` and `develop`, and on PRs targeting either branch.
It validates updater shell syntax, runs `nix flake check --show-trace`,
builds `checks.x86_64-linux.rocinante-toplevel`, and verifies the treefmt
check.

### Rebase develop onto main (`rebase-develop-onto-main.yml`)

Runs on every push to `main`, nightly, and manually. Keeps `main` an
ancestor of `develop` by fast-forwarding `develop` when possible, otherwise
rebasing `develop` onto `main` and force-pushing with lease.

### Update Dependency Pins (`update-pins.yml`)

Runs daily and manually. Resolves lockfile and Orca IDE pin updates, then
validates the change **in-workflow** (`nix flake check --no-build` plus the
full `rocinante` toplevel build) before committing. If validation fails,
nothing is committed. On success it commits only `flake.lock` and
`packages/orca-ide/default.nix` straight to `main`; the sync workflow then
carries the update into `develop`.

Pin updates land on `main` rather than `develop` because they are
maintenance ("keep `main` fresh"), not features: promotion stays a clean
fast-forward, and a future daily laptop update feed following `main`
receives fresh pins without waiting for a release.

## Design rationale and future hardening

The bot pushes directly to `main` after in-workflow validation instead of
opening a PR with required checks and native auto-merge. That PR-based flow
requires a GitHub App (or enabling "GitHub Actions may create and approve
pull requests") so the PR triggers normal CI — acceptable overhead for a
team, deliberately avoided for a solo repo. If the repository gains
collaborators, revisit: create a narrowly scoped GitHub App, restore PR
creation in `update-pins.yml`, and let branch protection enforce the gate
instead of the workflow.

## Future delivery (not yet implemented)

The intended end state: CI publishes the built `rocinante` closure to a
private binary cache (Attic on an always-on Tailscale-reachable VM;
Harmonia as a lighter alternative), and the laptop follows
`github:KostaGorod/nix-config` `main` daily with `system.autoUpgrade`
(`upgrade = false`, `operation = "boot"`, `--max-jobs 0` so cache misses
fail instead of compiling locally).

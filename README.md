# nix-config

Fully declarative NixOS configuration for my daily-driver ThinkPad (`rocinante`).

Plasma 6 and COSMIC side by side, hardware-backed SSH (TPM + YubiKey + fingerprint),
Tailscale mesh, agenix-managed secrets, and a growing set of AI coding tools
(Claude Code, OpenCode, and Droids). Mem0 and the standalone Qdrant container
are available as optional modules but currently disabled.
Power management is tuned per-profile with TLP, battery-health thresholds, and
runtime PM tweaks.

Editors (Helix, VSCode, Zed), shell tools (Bash + Starship + Direnv), and desktop apps
are managed by NixOS. Kosta's application packages and Git configuration are scoped
to that user; program defaults that use NixOS's global `programs.*` options remain
system-wide. Spotify is patched with SpotX, and wl-clipboard includes
sensitive-clipboard support for password managers.

## Updating dependency pins

Check the latest Orca release metadata without downloading the AppImage or
changing the repository:

```sh
scripts/update-orca-ide.sh --check
scripts/update-orca-ide.sh --check --json
```

Prepare a private `flake.lock` candidate and report available updates without
changing tracked files:

```sh
scripts/update-pins.sh --check
scripts/update-pins.sh --check --json
```

After reviewing the exact Orca version and GitHub API digest reported by
`--check`, apply both pins together from a completely clean worktree:

```sh
scripts/update-pins.sh --apply \
  --orca-version 1.4.179 \
  --orca-asset-digest sha256:078084856db66d29b26b5760b88028de95affcd771431359eee36924297b10df
```

The scripts validate exact release and asset metadata, use fixed-output hashes,
and refuse same-version, downgrade, malformed, mismatched, or dirty-worktree
updates. GitHub release digests establish integrity but do not independently
authenticate unsigned upstream releases, so review the release and diff before
merging.

`.github/workflows/update-pins.yml` checks weekly and can be started manually in
dry-run mode. It opens or refreshes a dedicated bot pull request only when a
reviewable diff exists. Regular pull-request CI validates the change; updating
pins is deliberately separate from rebuilding, switching, restarting, or
deploying the host.

## Deploy

```sh
sudo nixos-rebuild switch --flake .#rocinante
```

## Secrets quick start

1. Add the new encrypted file and its allowed public-key recipients to
   `secrets.nix`:
   ```nix
   "secrets/my-api-key.age".publicKeys = hosts ++ [
     "ssh-ed25519 AAAA... operator"
   ];
   ```
2. Create or edit it using a private key whose public key is in that recipient
   list:
   ```sh
   nix run github:ryantm/agenix -- \
     -e secrets/my-api-key.age \
     -i ~/.ssh/id_ed25519_secrets_management
   ```
3. Declare its runtime path and the account allowed to read it in an active
   dendritic module, such as `modules/security/secrets.nix`:
   ```nix
   age.secrets.my-api-key = {
     file = ../../secrets/my-api-key.age;
     path = "/run/secrets/my-api-key";
     owner = "my-app";
     group = "my-app";
     mode = "0400";
   };
   ```
4. Give the application the path, not the plaintext value:
   ```nix
   services.my-app.apiKeyFile = config.age.secrets.my-api-key.path;
   ```

See [`docs/SECRETS.md`](docs/SECRETS.md) for complete recipient, permission,
systemd credential, rekeying, and verification examples.

See [`modules/hosts/rocinante/README.md`](modules/hosts/rocinante/README.md) for hardware
details and first-time bootstrap, [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
for the design, and [`docs/SECRETS.md`](docs/SECRETS.md) for the agenix
workflow.

## Layout

| Path                 | Purpose                                                        |
|----------------------|----------------------------------------------------------------|
| `flake.nix`          | Inputs and the minimal dendritic `import-tree` entry point      |
| `modules/framework/` | Typed deferred-module framework, checks, and formatting         |
| `modules/hosts/`     | Host composition and machine-specific contributions            |
| `modules/users/`     | User-scoped packages, configuration, and migrations             |
| `modules/{concern}/` | Auto-imported feature contributions grouped by concern          |
| `overlays/`          | Package overlays retained for reuse, outside the import tree    |
| `packages/`          | Locally built package functions, outside the import tree        |
| `secrets/`           | Age-encrypted secrets (see `docs/SECRETS.md`)                   |
| `flakes/`            | Standalone dev shells; see `flakes/README.md`                   |
| `docs/`              | Architecture notes and setup guides                             |

Every non-underscore Nix file under `modules/` is a flake-parts top-level
module. Features merge into `nixos.modules.workstation`, user fragments merge
into `nixos.modules.kosta`, and host policy merges into the rocinante deferred
module. There is no central feature import list.

Top-level features capture the specific flake inputs they need lexically;
inputs are not passed wholesale into the NixOS module evaluation.

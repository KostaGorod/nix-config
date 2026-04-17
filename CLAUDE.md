# Agent notes

- NixOS flake configuration. Treat `flake.nix` as the source of truth.
- Format with `nix fmt` (treefmt wraps nixfmt, deadnix, statix) before committing.
- Verify changes with `nix flake check --no-build` and
  `nix build .#checks.x86_64-linux.rocinante-toplevel`.
- Secrets are age-encrypted in `secrets/`; never commit plaintext credentials.
  See `docs/SECRETS.md`.
- Commit messages follow conventional-ish prefixes (`feat`, `fix`, `chore`,
  `refactor`, `module`, `host`). Check `git log` for style.

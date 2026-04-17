# Secrets

Secrets are age-encrypted with [agenix][agenix] and decrypted at activation
into `/run/secrets/`.

## Layout

| File                             | Consumer                           |
|----------------------------------|------------------------------------|
| `secrets.nix`                    | Declares which keys can read what  |
| `secrets/voyage-api-key.age`     | `mem0` (VoyageAI embeddings)       |
| `secrets/anthropic-api-key.age`  | `mem0` (Claude LLM for extraction) |
| `modules/nixos/secrets.nix`      | Wires `age.secrets.<name>`         |

The host's SSH host key (`/etc/ssh/ssh_host_ed25519_key`) is the decryption
identity at boot. A user identity
(`/home/kosta/.ssh/id_ed25519_secrets_management`) is used locally for
`agenix -e`.

## Adding a secret

1. Add the host's ed25519 public key to `secrets.nix` if it isn't already.
2. Add the file to the `secrets.nix` output, e.g.:
   ```nix
   "secrets/openai-api-key.age".publicKeys = hosts;
   ```
3. Create and encrypt it:
   ```sh
   nix run github:ryantm/agenix -- -e secrets/openai-api-key.age
   ```
4. Reference it from a module:
   ```nix
   age.secrets.openai-api-key = {
     file = ../../secrets/openai-api-key.age;
     mode = "0400";
   };
   ```
5. Consume via `/run/secrets/openai-api-key`.

## Bootstrapping a fresh host

```sh
# 1. Install NixOS with SSH host keys generated.
# 2. Copy the new host's ssh_host_ed25519_key.pub into secrets.nix.
# 3. Re-encrypt so the new host can read existing secrets:
nix run github:ryantm/agenix -- --rekey
# 4. Commit, rebuild, reboot.
```

## What is *not* encrypted

- API keys live in `/run/secrets/*` at runtime; never on disk in plaintext.
- No plaintext credentials or `.env` files are tracked. The `.gitignore`
  reinforces this (`**/keys.txt`, `**/*.age.key`, `.config/nixos-secrets/`).

[agenix]: https://github.com/ryantm/agenix

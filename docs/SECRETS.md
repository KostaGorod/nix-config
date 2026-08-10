# Secrets

This repository uses [agenix][agenix] to keep encrypted payloads in Git and
decrypt them during NixOS activation. Although agenix defaults to
`/run/agenix/<name>`, every runtime secret in this repository must set an
explicit path under `/run/secrets/`.

## How the pieces fit together

| Location | Purpose |
|---|---|
| `secrets.nix` | Lists the public-key recipients allowed to decrypt each encrypted file |
| `secrets/*.age` | Encrypted payloads that are safe to commit |
| `modules/security/secrets.nix` | Declares runtime path, owner, group, and mode |
| `/run/secrets/<name>` | Decrypted runtime file, recreated during activation |

Current encrypted payloads:

| Secret | Consumer when enabled |
|---|---|
| `secrets/voyage-api-key.age` | Mem0 VoyageAI embeddings |
| `secrets/anthropic-api-key.age` | Mem0 LLM extraction |

Mem0 is currently disabled, so these secrets are not decrypted until
`services.mem0.enable` is set to `true`.

## Add a secret

### 1. Add recipients

Add the encrypted filename to `secrets.nix`. A recipient is a public key; its
matching private key is required to edit or decrypt the file.

```nix
let
  rocinante = "ssh-ed25519 AAAA... host";
  operator = "ssh-ed25519 AAAA... operator";

  hosts = [ rocinante ];
  operators = [ operator ];
in
{
  "secrets/my-api-key.age".publicKeys = hosts ++ operators;
}
```

Obtain public keys without copying private material:

```sh
# Host recipient
sudo cat /etc/ssh/ssh_host_ed25519_key.pub

# Operator recipient
ssh-keygen -y -f ~/.ssh/id_ed25519_secrets_management
```

`age.identityPaths` controls which private keys NixOS tries at boot. It does
not add recipients to encrypted files. To edit using an operator private key,
that operator's public key must appear in `secrets.nix`.

### 2. Create or edit the encrypted file

Run from the repository root, using a private key that matches one of the
configured recipients:

```sh
nix run github:ryantm/agenix -- \
  -e secrets/my-api-key.age \
  -i ~/.ssh/id_ed25519_secrets_management
```

The editor receives plaintext temporarily; save and exit to write the
age-encrypted file. Never create a plaintext copy inside the repository.

### 3. Declare the runtime secret

Add the declaration to an active dendritic module. For a host-level secret,
`modules/security/secrets.nix` is the usual location:

```nix
_: {
  nixos.configurations.rocinante.module =
    { config, ... }:
    {
      age.secrets.my-api-key = {
        file = ../../secrets/my-api-key.age;
        path = "/run/secrets/my-api-key";
        owner = "my-app";
        group = "my-app";
        mode = "0400";
      };

      services.my-app.apiKeyFile = config.age.secrets.my-api-key.path;
    };
}
```

The application receives a path such as `/run/secrets/my-api-key`; the secret
value is not evaluated by Nix and does not enter the Nix store.

## Allow an application to use a secret

Use the narrowest pattern supported by the application.

### Application supports a file option

Set the decrypted file's ownership to the service account and pass the path:

```nix
age.secrets.my-api-key = {
  file = ../../secrets/my-api-key.age;
  path = "/run/secrets/my-api-key";
  owner = "my-app";
  group = "my-app";
  mode = "0400";
};

services.my-app.apiKeyFile = config.age.secrets.my-api-key.path;
```

For a normal user application, use that user's account, for example
`owner = "kosta"` and `group = "users"`.

### Application requires an environment variable

Keep the source secret root-owned and let systemd copy it into a private
credential directory for the service:

```nix
age.secrets.my-api-key = {
  file = ../../secrets/my-api-key.age;
  path = "/run/secrets/my-api-key";
  owner = "root";
  group = "root";
  mode = "0400";
};

systemd.services.my-app = {
  serviceConfig = {
    User = "my-app";
    LoadCredential = [
      "api-key:${config.age.secrets.my-api-key.path}"
    ];
  };

  script = ''
    export API_KEY="$(<"$CREDENTIALS_DIRECTORY/api-key")"
    exec ${pkgs.my-app}/bin/my-app
  '';
};
```

Do not put the plaintext in `environment`, `Environment=`, command-line
arguments, or generated Nix files; those values can become visible through the
Nix store, process listings, or service metadata.

## Rebuild and verify

```sh
sudo nixos-rebuild switch --flake .#rocinante

# Verify metadata without printing the secret.
sudo stat -c '%U:%G %a %n' /run/secrets/my-api-key
sudo -u my-app test -r /run/secrets/my-api-key
```

If the second command exits successfully, the selected service account can
read the secret. Do not use `cat` as a connectivity test.

## Change recipients or add a host

1. Add the new public key to `secrets.nix`.
2. Rekey using an existing matching private key:
   ```sh
   nix run github:ryantm/agenix -- \
     --rekey \
     -i ~/.ssh/id_ed25519_secrets_management
   ```
3. Commit the updated encrypted files and rebuild the target host.

For a fresh host, add `/etc/ssh/ssh_host_ed25519_key.pub` as a recipient before
rekeying. The target host must possess at least one matching private identity at
activation time.

## Safety rules

- Commit only `.age` files, never plaintext credentials or `.env` files.
- Never use `builtins.readFile` on a decrypted runtime secret; that can copy the
  value into the Nix store.
- Pass `config.age.secrets.<name>.path` to applications instead of reading the
  value during evaluation.
- Grant access with the narrowest owner/group/mode or a systemd credential.
- Do not make `/run/secrets` globally readable.
- Review `git diff` before committing to ensure no plaintext was added.

[agenix]: https://github.com/ryantm/agenix

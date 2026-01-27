# agenix secrets configuration
# Decrypts secrets at activation and places them in /run/secrets/
{ config, lib, ... }:

{
  # Host-specific identity paths for agenix
  # rocinante: user's secrets management key (no SSH host key exists)
  # gpu-node-1: standard SSH host key
  age.identityPaths = if config.networking.hostName == "rocinante"
    then [ "/home/kosta/.ssh/id_ed25519_secrets_management" ]
    else [ "/etc/ssh/ssh_host_ed25519_key" ];

  # Symlink /run/agenix to /run/secrets for conventional path
  age.secretsDir = "/run/secrets";

  age.secrets = {
    voyage-api-key = {
      file = ../../secrets/voyage-api-key.age;
      owner = "mem0";
      group = "mem0";
      mode = "0400";
    };

    anthropic-api-key = {
      file = ../../secrets/anthropic-api-key.age;
      owner = "mem0";
      group = "mem0";
      mode = "0400";
    };

    github-runner-token = {
      file = ../../secrets/github-runner-token.age;
      mode = "0400";
    };
  };
}

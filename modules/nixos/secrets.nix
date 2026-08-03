# agenix secrets configuration
# Decrypts secrets at activation and places them in /run/secrets/
{ config, lib, ... }:
let
  mem0Ownership = lib.optionalAttrs config.services.mem0.enable {
    owner = "mem0";
    group = "mem0";
  };
in
{
  # Age identities for decryption
  age.identityPaths = [
    "/etc/ssh/ssh_host_ed25519_key"
    "/home/kosta/.ssh/id_ed25519_secrets_management"
  ];

  age.secrets = {
    voyage-api-key = {
      file = ../../secrets/voyage-api-key.age;
      mode = "0400";
    }
    // mem0Ownership;

    anthropic-api-key = {
      file = ../../secrets/anthropic-api-key.age;
      mode = "0400";
    }
    // mem0Ownership;
  };
}

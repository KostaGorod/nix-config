# agenix secrets configuration
# Decrypts secrets at activation and places them in /run/secrets/
{ config, lib, ... }:

{
  # Default age identity (SSH host key)
  age.identityPaths = [
    "/etc/ssh/ssh_host_ed25519_key"
  ];

  # Declare secrets to decrypt
  age.secrets = {
    voyage-api-key = {
      file = ../../secrets/voyage-api-key.age;
      path = "/run/secrets/voyage-api-key";
      owner = "root";
      group = "root";
      mode = "0400";
    };

    anthropic-api-key = {
      file = ../../secrets/anthropic-api-key.age;
      path = "/run/secrets/anthropic-api-key";
      owner = "root";
      group = "root";
      mode = "0400";
    };

    # Add more secrets as needed:
    # github-token = {
    #   file = ../../secrets/github-token.age;
    #   path = "/run/secrets/github-token";
    #   mode = "0400";
    # };
  };
}

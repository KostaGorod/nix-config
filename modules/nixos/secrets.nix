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
     github-action-token = {
       file = ../../secrets/github-action-token.age;
       path = "/run/secrets/github-action-token";
       owner = "root";
       group = "root";
       mode = "0400";
     };
    # give secret to service as a different user
    # age.secrets.some-secret = {
    # file = ../../secrets/some-secret.age;
    # path = "/run/secrets/some-secret";
    # owner = "myservice";  # the user running the service
    # group = "myservice";
    # mode = "0400";
    # };
  };
}

# agenix secrets configuration
# Decrypts secrets at activation and places them in /run/secrets/
_:

{
  # Age identities for decryption
  age.identityPaths = [
    "/etc/ssh/ssh_host_ed25519_key"
    "/home/kosta/.ssh/id_ed25519_secrets_management"
  ];

  age.secrets = {
    voyage-api-key = {
      file = ../../secrets/voyage-api-key.age;
      #owner = "mem0";
      #group = "mem0";
      mode = "0400";
    };

    anthropic-api-key = {
      file = ../../secrets/anthropic-api-key.age;
      #owner = "mem0";
      #group = "mem0";
      mode = "0400";
    };

    github-runner-token = {
      file = ../../secrets/github-runner-token.age;
      mode = "0400";
    };
  };
}

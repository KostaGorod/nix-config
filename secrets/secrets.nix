# agenix secrets definition
# Run: agenix -e secrets/<name>.age to create/edit secrets
#
# To get your SSH public keys:
#   Host key:  cat /etc/ssh/ssh_host_ed25519_key.pub
#   User key:  cat ~/.ssh/id_ed25519.pub
let
  # Host SSH public keys (from /etc/ssh/ssh_host_ed25519_key.pub)
  # TODO: Replace with actual keys after running: cat /etc/ssh/ssh_host_ed25519_key.pub
  rocinante = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI_REPLACE_WITH_ROCINANTE_HOST_KEY";
  gpu-node-1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI_REPLACE_WITH_GPU_NODE_1_HOST_KEY";

  # User SSH public keys (from ~/.ssh/id_ed25519.pub)
  # TODO: Replace with actual key after running: cat ~/.ssh/id_ed25519.pub
  kosta = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI_REPLACE_WITH_KOSTA_USER_KEY";

  # Key groups
  allHosts = [ rocinante gpu-node-1 ];
  allUsers = [ kosta ];
  all = allHosts ++ allUsers;
in
{
  # API keys for mem0 service
  "voyage-api-key.age".publicKeys = all;
  "anthropic-api-key.age".publicKeys = all;

  # Add more secrets as needed:
  # "github-token.age".publicKeys = all;
  # "openai-api-key.age".publicKeys = all;
}

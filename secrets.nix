# agenix secrets definition
# Run: agenix -e secrets/<name>.age to create/edit secrets
#
# To get your SSH public keys:
#   Host key:  cat /etc/ssh/ssh_host_ed25519_key.pub
#   User key:  cat ~/.ssh/id_ed25519.pub
let
  # Host SSH public keys (from /etc/ssh/ssh_host_ed25519_key.pub)
  rocinante = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMWNLmrawXcnqlEYu7didRGN+OvKlQy+fnV+oYD3tzzR kosta@rocinante";
  gpu-node-1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOXf9Q8jJ6iRak+MEuJ29QMn273k2PBSrX7tckxsDr3z";

  # User SSH public keys (from ~/.ssh/id_ed25519.pub)
  # TODO: Replace with actual key after running: cat ~/.ssh/id_ed25519.pub
  # kosta = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI_REPLACE_WITH_KOSTA_USER_KEY";

  # Key groups
  adminHosts = [ rocinante ];
  allHosts = [ rocinante gpu-node-1 ];
  # allUsers = [  ];
  all = allHosts;
  # all = allHosts ++ allUsers;
in
{
  # API keys for mem0 service (paths from repo root)
  "secrets/voyage-api-key.age".publicKeys = all;
  "secrets/anthropic-api-key.age".publicKeys = all;
  "secrets/github-runner-token.age".publicKeys = adminHosts ++ [ gpu-node-1 ]; # unique token for each host
  # Add more secrets as needed:
  # "secrets/github-token.age".publicKeys = all;
}

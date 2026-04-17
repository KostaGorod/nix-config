# agenix secrets definition
# Run: agenix -e secrets/<name>.age to create/edit secrets
#
# To get your SSH public keys:
#   Host key:  cat /etc/ssh/ssh_host_ed25519_key.pub
#   User key:  cat ~/.ssh/id_ed25519.pub
let
  # Host SSH public keys (from /etc/ssh/ssh_host_ed25519_key.pub)
  rocinante = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMWNLmrawXcnqlEYu7didRGN+OvKlQy+fnV+oYD3tzzR kosta@rocinante";

  hosts = [ rocinante ];
in
{
  "secrets/voyage-api-key.age".publicKeys = hosts;
  "secrets/anthropic-api-key.age".publicKeys = hosts;
}

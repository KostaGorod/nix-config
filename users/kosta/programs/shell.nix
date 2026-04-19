# Shell configuration for kosta
# Bash, starship, direnv, carapace
_: {
  # Bash
  programs.bash = {
    enable = true;
    enableCompletion = true;
    shellAliases = {
      l = "ls";
      ll = "ls -la";
      la = "ls -a";
      gs = "git status";
      gl = "git log";
      g = "git";
      k = "kubectl";
      nftest = "cd /home/kosta/nix-config && nix flake check --flake .#rocinante";
      nfswitch = "cd /home/kosta/nix-config && sudo nixos-rebuild switch --flake .#rocinante";
      nftestswitch = "nftest && nfswitch";
    };
    bashrcExtra = ''
      export PATH="$PATH:$HOME/bin:$HOME/.local/bin"

      # pam_gnome_keyring (enabled for Bitwarden Secret Service) rewrites
      # SSH_AUTH_SOCK to $XDG_RUNTIME_DIR/keyring/ssh during the PAM session,
      # but the keyring's ssh component isn't actually started — so the
      # socket doesn't exist. Restore the path to OpenSSH's agent here so
      # non-login shells spawned from the graphical session use it.
      if [ -n "$XDG_RUNTIME_DIR" ]; then
        export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent"
      fi
    '';
  };

  # Starship prompt
  programs.starship = {
    enable = true;
    settings = {
      add_newline = true;
      aws.disabled = false;
      gcloud.disabled = true;
      line_break.disabled = true;
    };
  };

  # Direnv for automatic environment loading
  programs.direnv.enable = true;

  # Carapace multi-shell completion
  programs.carapace = {
    enable = true;
    enableBashIntegration = true;
  };
}

# Workstation shell defaults
# Bash, starship, direnv, carapace
_: {
  nixos.modules.workstation = { pkgs, ... }: {
    environment.localBinInPath = true;

    # Bash
    programs.bash = {
      enable = true;
      completion.enable = true;
      shellInit = ''
        export PATH="$PATH:$HOME/bin"
      '';
      interactiveShellInit = ''
        HISTFILESIZE=100000
        HISTSIZE=10000
        shopt -s histappend extglob globstar checkjobs
        source <(${pkgs.carapace}/bin/carapace _carapace bash)
      '';
      shellAliases = {
        l = "ls";
        ll = "ls -la";
        la = "ls -a";
        gs = "git status";
        gl = "git log";
        g = "git";
        k = "kubectl";
        nftest = "cd /home/kosta/nix-config && nix flake check";
        nfswitch = "cd /home/kosta/nix-config && sudo nixos-rebuild switch --flake .#rocinante";
        nftestswitch = "nftest && nfswitch";
      };
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

  };
}

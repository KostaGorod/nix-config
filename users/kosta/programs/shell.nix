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
    };
    bashrcExtra = ''
      export PATH="$PATH:$HOME/bin:$HOME/.local/bin"
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

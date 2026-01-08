# Git configuration for kosta
{ pkgs, lib, ... }:
{
  # Git with libsecret credential storage
  programs.git = {
    package = pkgs.gitFull;
    enable = true;
    settings = {
      user.name = "Kosta Gorod";
      user.email = "korolx147@gmail.com";
      credential.helper = lib.mkBefore [
        "${pkgs.gitFull.override { withLibsecret = true; }}/bin/git-credential-libsecret"
      ];
    };
  };

  # OAuth support for git
  programs.git-credential-oauth.enable = true;

  # GitHub CLI
  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
  };
}

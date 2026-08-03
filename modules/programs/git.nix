_: {
  nixos.modules.workstation = { pkgs, ... }: {
    programs.git = {
      enable = true;
      package = pkgs.gitFull.override { withLibsecret = true; };
    };
  };
}

_: {
  perSystem =
    { pkgs, ... }:
    {
      packages.memvid = pkgs.callPackage ../../packages/memvid { };
    };

  nixos.modules.workstation =
    {
      config,
      lib,
      pkgs,
      ...
    }:

    let
      memvid = pkgs.callPackage ../../packages/memvid { };
      repo-mem = pkgs.writeShellApplication {
        name = "repo-mem";
        runtimeInputs = [ memvid ];
        text = ''
          exec ${pkgs.python3}/bin/python ${../../packages/memvid/repo-mem.py} "$@"
        '';
      };
    in
    {
      options.programs.memvid.enable = lib.mkEnableOption "Memvid local repository index tools";

      config = lib.mkIf config.programs.memvid.enable {
        environment.systemPackages = [
          memvid
          repo-mem
        ];
      };
    };
}
